require "test_helper"

class FaqSearchTest < ActiveSupport::TestCase
  setup do
    FaqEntry.sync!(embedder: Embedder.default)
    @search = FaqSearch.new
  end

  test "finds the entry that answers the question" do
    result = @search.call("can I delete an applicant")
    assert_includes result.hits.map(&:key), "applicants:7"
  end

  test "keyword search finds rare exact terms and weights them by rarity" do
    hit = @search.call("409").hits.find { |h| h.key == "technical:1" }

    assert hit, "the only entry mentioning 409 should be retrieved"
    assert hit.keyword_rank
    assert_operator hit.keyword_score, :>=, FaqSearch::KEYWORD_EVIDENCE
  end

  test "hits found by both searches outrank hits found by one" do
    hits = @search.call("idempotency keys remembered").hits
    assert_equal "technical:2", hits.first.key
    assert hits.first.vector_rank && hits.first.keyword_rank
  end

  test "returns at most the requested number of hits" do
    assert_equal 2, @search.call("rules", limit: 2).hits.size
  end

  test "a question is covered by a close meaning match or by a rare shared term" do
    entry = FaqEntry.first
    hit = ->(similarity:, keyword_score: nil) {
      FaqSearch::Hit.new(entry: entry, similarity: similarity, vector_rank: 1, keyword_rank: nil, keyword_score: keyword_score, score: 0)
    }

    assert FaqSearch::Result.new(hits: [ hit.(similarity: 0.7) ], top_similarity: 0.7).relevant?
    assert FaqSearch::Result.new(hits: [ hit.(similarity: 0.45, keyword_score: 3.5) ], top_similarity: 0.45).relevant?
    assert_not FaqSearch::Result.new(hits: [ hit.(similarity: 0.45, keyword_score: 1.0) ], top_similarity: 0.45).relevant?
    assert_not FaqSearch::Result.new(hits: [ hit.(similarity: 0.2, keyword_score: 5.0) ], top_similarity: 0.2).relevant?
    assert_not FaqSearch::Result.new(hits: [], top_similarity: nil).relevant?
  end
end
