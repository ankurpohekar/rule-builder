# Every question asked to the FAQ bot, with what it retrieved and answered. Unanswered and
# thumbs-down questions show which FAQ entries to add or improve.
class CreateFaqQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :faq_questions do |t|
      t.text :question, null: false
      t.text :answer
      t.boolean :answered, null: false, default: false
      t.jsonb :retrieved, null: false, default: [] # [{ key:, vector_rank:, keyword_rank:, similarity: }]
      t.string :sources, array: true, null: false, default: []
      t.float :top_similarity
      t.integer :feedback # 1 helpful, -1 not helpful
      t.integer :duration_ms
      t.timestamps
    end

    add_index :faq_questions, :created_at
    add_index :faq_questions, :answered
  end
end
