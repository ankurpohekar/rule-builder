# Hybrid search over the FAQ index: the "retrieval" step of the FAQ bot.
#
# Two searches run side by side and their rankings are merged:
# - Vector search finds entries with the same *meaning* ("undo removing a person" → "delete an applicant").
# - Keyword search finds exact *terms* that embeddings blur ("409", "Idempotency-Key"). Each matched
#   word counts by how rare it is in the FAQ (IDF, as in BM25), so "409" outweighs "mean".
# Reciprocal rank fusion (RRF) merges the two lists using only ranks, so the scores of the two
# searches never need to be on the same scale.
#
#   FaqSearch.new.call("can I undo a delete?").hits.first(3)
#   # => [#<FaqSearch::Hit key="applicants:7" similarity=0.69 vector_rank=1 keyword_rank=nil ...>, ...]
class FaqSearch
  # How many candidates each search contributes before merging.
  CANDIDATES = 20
  # RRF constant: larger values flatten the advantage of the very top ranks. 60 is the usual default.
  RRF_K = 60
  # How much each list counts in the merge. Measured with script/faq_eval.rb on this FAQ: equal
  # weights let keyword matches on common words ("applicant", "rule") push weak entries above the
  # best meaning-match (hit@1 64% vs 76% for vectors alone). At 0.25 keywords mostly break ties and
  # still lift rare exact terms like "409" into the top 5. Re-run the eval when the FAQ grows.
  WEIGHTS = { vector: 1.0, keyword: 0.25 }.freeze

  # A question counts as covered by the FAQ when the best meaning-match reaches MIN_SIMILARITY,
  # or when an entry shares a rare term with it (KEYWORD_EVIDENCE: a word found in at most two
  # entries) and is at least loosely related (KEYWORD_MIN_SIMILARITY). Tuned with script/faq_eval.rb.
  # This is a cheap pre-filter that leans towards letting questions through: a false pass costs one
  # LLM call (which then says the FAQ doesn't cover it), a false fail loses an answer the FAQ has.
  MIN_SIMILARITY = 0.6
  KEYWORD_EVIDENCE = 3.0
  KEYWORD_MIN_SIMILARITY = 0.4

  Hit = Data.define(:entry, :similarity, :vector_rank, :keyword_rank, :keyword_score, :score) do
    delegate :key, to: :entry

    def to_log
      { key: key, similarity: similarity.round(4), vector_rank: vector_rank,
        keyword_rank: keyword_rank, keyword_score: keyword_score&.round(2) }
    end
  end

  Result = Data.define(:hits, :top_similarity) do
    # Questions that fail this get "not in the FAQ" without calling the LLM.
    def relevant?
      top_similarity.to_f >= MIN_SIMILARITY ||
        hits.any? { |hit| hit.keyword_score.to_f >= KEYWORD_EVIDENCE && hit.similarity >= KEYWORD_MIN_SIMILARITY }
    end
  end

  def initialize(embedder: Embedder.default, weights: WEIGHTS)
    @embedder = embedder
    @weights = weights
  end

  def call(query, limit: 5)
    query_embedding = @embedder.embed_query(query)

    vector_hits = FaqEntry.nearest_neighbors(:embedding, query_embedding, distance: "cosine").first(CANDIDATES)
    keyword_hits = keyword_search(query)

    vector_rank = vector_hits.each_with_index.to_h { |entry, i| [ entry.id, i + 1 ] }
    keyword_rank = keyword_hits.each_with_index.to_h { |entry, i| [ entry.id, i + 1 ] }
    similarity = vector_hits.to_h { |entry| [ entry.id, 1 - entry.neighbor_distance ] }

    hits = (vector_hits + keyword_hits).uniq(&:id).map do |entry|
      keyword_hit = keyword_hits.find { |hit| hit.id == entry.id }
      Hit.new(entry: entry,
              # Keyword-only hits weren't in the vector top list, so compute their similarity directly.
              similarity: similarity[entry.id] || dot(entry.embedding, query_embedding),
              vector_rank: vector_rank[entry.id], keyword_rank: keyword_rank[entry.id],
              keyword_score: keyword_hit&.keyword_score&.to_f,
              score: rrf(vector_rank[entry.id], :vector) + rrf(keyword_rank[entry.id], :keyword))
    end

    Result.new(hits: hits.sort_by { |hit| -hit.score }.first(limit), top_similarity: similarity.values.max)
  end

  private
    # Scores each entry by the summed IDF of the query words it contains. Postgres full-text
    # ranking (ts_rank) has no notion of rarity, so IDF comes from ts_stat over the index.
    def keyword_search(query)
      words = FaqEntry.connection.select_values(
        FaqEntry.sanitize_sql_array([ "SELECT DISTINCT unnest(tsvector_to_array(to_tsvector('english', ?)))", query ])
      )
      weights = words.filter_map { |word| [ word, idf[word] ] if idf[word] }
      return [] if weights.empty?

      score = weights.map { |word, weight| FaqEntry.sanitize_sql_array([ "(CASE WHEN searchable @@ quote_literal(?)::tsquery THEN ? ELSE 0 END)", word, weight ]) }.join(" + ")
      FaqEntry.select("faq_entries.*, #{score} AS keyword_score")
        .where("(#{score}) > 0").order("keyword_score DESC").limit(CANDIDATES).to_a
    end

    # BM25's IDF for every word in the index: log(1 + (N - n + 0.5) / (n + 0.5)), where n is the
    # number of entries containing the word. Cached until the index changes.
    def idf
      version = FaqEntry.pick(Arel.sql("count(*), max(updated_at)"))
      self.class.idf_cache = nil if self.class.idf_cache&.first != version
      self.class.idf_cache ||= begin
        total = version.first.to_f
        stats = FaqEntry.connection.select_rows("SELECT word, ndoc FROM ts_stat('SELECT searchable FROM faq_entries')")
        [ version, stats.to_h { |word, ndoc| [ word, Math.log(1 + (total - ndoc + 0.5) / (ndoc + 0.5)) ] } ]
      end
      self.class.idf_cache.last
    end

    def rrf(rank, list) = rank ? @weights.fetch(list) / (RRF_K + rank) : 0.0

    def dot(a, b) = a.zip(b).sum { |x, y| x * y } # embeddings are normalized, so this is cosine similarity

  class_attribute :idf_cache
end
