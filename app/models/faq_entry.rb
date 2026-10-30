# One FAQ question in the bot's search index: a copy of an item from config/faq.yml plus its
# embedding. config/faq.yml stays the source of truth; FaqEntry.sync! brings the index up to date.
class FaqEntry < ApplicationRecord
  has_neighbors :embedding, dimensions: Embedder::DIMENSIONS

  # Makes the index match config/faq.yml: adds new questions, updates edited ones, removes
  # deleted ones, and embeds only entries whose text (or the embedding model) changed.
  # Returns { embedded:, removed:, total: }.
  def self.sync!(embedder: Embedder.default)
    items = Faq.items
    existing = all.index_by(&:key)

    stale = items.reject { |item| existing[item.key]&.content_digest == digest_for(item) }
    vectors = embedder.embed_documents(stale.map(&:content))

    transaction do
      stale.zip(vectors).each do |item, vector|
        entry = existing[item.key] || new(key: item.key)
        entry.update!(section_title: item.section_title, question: item.question, answer: item.answer,
                      content_digest: digest_for(item), embedding: vector)
      end
      removed = where.not(key: items.map(&:key)).delete_all
      { embedded: stale.size, removed: removed, total: items.size }
    end
  end

  # Changes when the text or the model changes; either way the old embedding no longer fits.
  def self.digest_for(item)
    Digest::SHA256.hexdigest("#{Embedder::MODEL}\n#{item.content}")
  end
end
