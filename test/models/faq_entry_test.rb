require "test_helper"

class FaqEntryTest < ActiveSupport::TestCase
  setup { @embedder = HashingEmbedder.new }

  test "sync indexes every FAQ item with an embedding" do
    result = FaqEntry.sync!(embedder: @embedder)

    assert_equal Faq.items.size, result[:embedded]
    assert_equal Faq.items.size, FaqEntry.count
    assert_equal Embedder::DIMENSIONS, FaqEntry.find_by(key: "rules:0").embedding.size
  end

  test "a second sync embeds nothing when nothing changed" do
    FaqEntry.sync!(embedder: @embedder)
    assert_equal 0, FaqEntry.sync!(embedder: @embedder)[:embedded]
    assert_equal Faq.items.size, @embedder.calls.flatten.size
  end

  test "only edited entries are embedded again, and deleted ones are removed" do
    FaqEntry.sync!(embedder: @embedder)
    FaqEntry.find_by(key: "rules:0").update!(content_digest: "edited")
    FaqEntry.create!(key: "gone:0", section_title: "Old", question: "Old?", answer: "Old.", content_digest: "x")

    result = FaqEntry.sync!(embedder: @embedder)

    assert_equal 1, result[:embedded]
    assert_equal 1, result[:removed]
    assert_not FaqEntry.exists?(key: "gone:0")
  end
end
