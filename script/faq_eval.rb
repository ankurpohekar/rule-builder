# Measures FAQ retrieval quality against script/faq_eval_questions.yml. No LLM calls: this
# checks the retrieval step alone, which is where most RAG failures start.
#
#   bin/rails runner script/faq_eval.rb            # all search modes
#   bin/rails runner script/faq_eval.rb --verbose  # also list each miss
#
# Metrics, for each search mode:
#   hit@1  share of covered questions whose expected entry is ranked first
#   hit@5  ... is anywhere in the 5 entries sent to Claude (what matters for answering)
#   MRR    mean reciprocal rank: 1 for rank 1, 0.5 for rank 2, ... 0 if missing
# and for the "is this covered?" pre-filter (the same in every mode):
#   covered passed     covered questions let through to Claude (want 100%)
#   off-topic blocked  off-topic questions stopped before Claude (higher saves LLM calls)
verbose = ARGV.include?("--verbose")
set = YAML.load_file(Rails.root.join("script/faq_eval_questions.yml"))

sync = FaqEntry.sync!
puts "Index: #{sync[:total]} entries (#{sync[:embedded]} embedded now)"

modes = {
  "vector only" => { vector: 1.0, keyword: 0.0 },
  "keyword only" => { vector: 0.0, keyword: 1.0 },
  "hybrid, equal" => { vector: 1.0, keyword: 1.0 },
  "hybrid, keyword x0.5" => { vector: 1.0, keyword: 0.5 },
  "hybrid, keyword x0.25" => { vector: 1.0, keyword: 0.25 }
}

# Embedding is the slow part, so embed each question once and reuse it across modes.
cache = Hash.new { |hash, text| hash[text] = Embedder.default.embed_query(text) }
cached_embedder = Struct.new(:cache) { def embed_query(text) = cache[text] }.new(cache)

modes.each do |name, weights|
  search = FaqSearch.new(embedder: cached_embedder, weights: weights)
  ranks = set["covered"].map do |example|
    # A zero-weight list adds nothing to the score, so drop its hits from the ranking too.
    hits = search.call(example["q"], limit: 20).hits
    hits = hits.select(&:vector_rank) if weights[:keyword].zero?
    hits = hits.select(&:keyword_rank) if weights[:vector].zero?
    rank = hits.first(5).index { |hit| example["expect"].include?(hit.key) }&.succ
    puts "  miss (#{name}): #{example['q']} → got #{hits.first(3).map(&:key).join(', ')}" if verbose && rank.nil?
    rank
  end

  total = ranks.size.to_f
  puts format("%-22s hit@1 %5.1f%%   hit@5 %5.1f%%   MRR %.3f", name,
              100 * ranks.count(1) / total, 100 * ranks.compact.size / total,
              ranks.sum { |rank| rank ? 1.0 / rank : 0 } / total)
end

# The pre-filter is checked with the app's own settings.
search = FaqSearch.new(embedder: cached_embedder)
misses = set["covered"].reject { |example| search.call(example["q"]).relevant? }.map { |example| example["q"] }
blocked = set["off_topic"].count { |question| !search.call(question).relevant? }
passed = set["covered"].size - misses.size
puts
puts "Current FaqSearch::WEIGHTS: #{FaqSearch::WEIGHTS}"
puts format("Pre-filter: covered passed %d/%d, off-topic blocked %d/%d  (MIN_SIMILARITY %.2f)",
            passed, set["covered"].size, blocked, set["off_topic"].size, FaqSearch::MIN_SIMILARITY)
misses.each { |question| puts "  wrongly blocked: #{question}" }
