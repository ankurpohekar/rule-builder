class Rule < ApplicationRecord
  OUTCOMES = %w[approved rejected pending].freeze

  has_many :matched_applicants, class_name: "Applicant", foreign_key: :matched_rule_id, dependent: :nullify

  validates :name, presence: true
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :priority, numericality: { only_integer: true }
  validate :conditions_are_valid

  scope :active, -> { where(active: true) }
  scope :by_priority, -> { order(:priority, :id) }

  # Any rule change can change which rule wins, so re-run every applicant in the background.
  # after_commit (not after_save) so the job never runs before the change is visible.
  after_commit -> { EvaluateApplicantsJob.enqueue }

  def matches?(applicant)
    ConditionTree.new(conditions).matches?(applicant)
  end

  private
    def conditions_are_valid
      ConditionTree.new(conditions).errors.each { |message| errors.add(:conditions, message) }
    end
end
