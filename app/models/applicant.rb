class Applicant < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze
  EMPLOYMENT_STATUSES = %w[employed self_employed unemployed student retired].freeze

  # Fields that rules may reference, with the type used to cast and compare values.
  FIELDS = {
    "age"               => { label: "Age", type: "number" },
    "credit_score"      => { label: "Credit score", type: "number" },
    "annual_income"     => { label: "Annual income", type: "number" },
    "employment_status" => { label: "Employment status", type: "enum", options: EMPLOYMENT_STATUSES },
    "country"           => { label: "Country", type: "string" },
    "email"             => { label: "Email", type: "string" },
    "name"              => { label: "Name", type: "string" }
  }.freeze

  belongs_to :matched_rule, class_name: "Rule", optional: true

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }
  validates :employment_status, inclusion: { in: EMPLOYMENT_STATUSES }, allow_nil: true
  validates :age, :credit_score, numericality: { only_integer: true, allow_nil: true }
  validates :annual_income, numericality: { greater_than_or_equal_to: 0, allow_nil: true }

  before_save :apply_rules, if: -> { new_record? || (changed & FIELDS.keys).any? }

  # Trigram indexes need at least 3 characters to narrow anything down.
  SUBSTRING_SEARCH_MIN_LENGTH = 3

  # Case-insensitive search on name and email. Terms of 3+ characters match anywhere
  # (trigram GIN indexes); shorter terms match the start only (lower(...) text_pattern_ops indexes).
  # Each branch is written to match its index expression exactly, or Postgres can't use it.
  scope :search, ->(term) {
    term = term.strip
    escaped = sanitize_sql_like(term) # measure length before escaping adds backslashes
    if term.length >= SUBSTRING_SEARCH_MIN_LENGTH
      where("applicants.name ILIKE :pattern OR applicants.email ILIKE :pattern", pattern: "%#{escaped}%")
    else
      where("lower(applicants.name) LIKE lower(:prefix) OR lower(applicants.email) LIKE lower(:prefix)", prefix: "#{escaped}%")
    end
  }

  EVALUATION_BATCH_SIZE = 1_000

  # Re-runs every applicant through the current rules, writing only applicants whose decision
  # changed. Each batch is matched in Ruby, then saved with one UPDATE per distinct
  # (status, rule) pair, so a batch costs a handful of queries instead of one save per row.
  #
  # update_all skips validations and callbacks: anything that must react to a status change
  # (e.g. emails) should be triggered here from the changed ids, not from model callbacks.
  # Returns the number of applicants whose decision changed.
  def self.evaluate_all!
    rules = Rule.active.by_priority.to_a
    changed = 0

    select(:id, :status, :matched_rule_id, *FIELDS.keys).find_in_batches(batch_size: EVALUATION_BATCH_SIZE) do |batch|
      ids_by_decision = Hash.new { |hash, key| hash[key] = [] }
      batch.each do |applicant|
        status, rule = decide(applicant, rules)
        next if status == applicant.status && rule&.id == applicant.matched_rule_id
        ids_by_decision[[ status, rule&.id ]] << applicant.id
      end

      now = Time.current
      ids_by_decision.each do |(status, rule_id), ids|
        changed += where(id: ids).update_all(status: status, matched_rule_id: rule_id, evaluated_at: now, updated_at: now)
      end
    end

    changed
  end

  # The first active rule (by priority) whose conditions match decides the status.
  # No match leaves the applicant pending.
  def self.decide(applicant, rules)
    rule = rules.find { |r| r.matches?(applicant) }
    [ rule&.outcome || "pending", rule ]
  end

  def apply_rules
    self.status, self.matched_rule = self.class.decide(self, Rule.active.by_priority.to_a)
    self.evaluated_at = Time.current
  end
end
