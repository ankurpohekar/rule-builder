# The FAQ bot's search index: one row per FAQ question (synced from config/faq.yml),
# with an embedding for meaning-based search and a tsvector for keyword search.
class CreateFaqEntries < ActiveRecord::Migration[8.1]
  def change
    enable_extension "vector"

    create_table :faq_entries do |t|
      t.string :key, null: false, index: { unique: true } # "rules:2", as in config/faq.yml
      t.string :section_title, null: false
      t.text :question, null: false
      t.text :answer, null: false
      # Digest of the embedded text plus the model name; a mismatch means the embedding is stale.
      t.string :content_digest, null: false
      t.vector :embedding, limit: 384 # BAAI/bge-small-en-v1.5 produces 384 dimensions
      t.virtual :searchable, type: :tsvector, stored: true,
        as: "setweight(to_tsvector('english', question), 'A') || setweight(to_tsvector('english', answer), 'B')"
      t.timestamps
    end

    # HNSW: approximate nearest-neighbour index for cosine distance (embeddings are normalized).
    add_index :faq_entries, :embedding, using: :hnsw, opclass: :vector_cosine_ops
    add_index :faq_entries, :searchable, using: :gin
  end
end
