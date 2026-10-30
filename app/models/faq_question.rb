# A question asked to the FAQ bot, kept to improve the FAQ: unanswered and unhelpful questions
# show which entries are missing or unclear.
class FaqQuestion < ApplicationRecord
  FEEDBACK = { helpful: 1, not_helpful: -1 }.freeze

  validates :question, presence: true
  validates :feedback, inclusion: { in: FEEDBACK.values }, allow_nil: true

  scope :unanswered, -> { where(answered: false) }
  scope :not_helpful, -> { where(feedback: FEEDBACK[:not_helpful]) }

  def self.record!(question, reply, duration_ms:)
    create!(question: question, answer: reply.text, answered: reply.answered, sources: reply.sources,
            retrieved: reply.search.hits.map(&:to_log), top_similarity: reply.search.top_similarity,
            duration_ms: duration_ms)
  end
end
