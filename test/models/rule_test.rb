require "test_helper"

class RuleTest < ActiveSupport::TestCase
  def condition(field, operator, value = nil)
    { field: field, operator: operator, value: value }
  end

  def rule(outcome, priority, *conditions, combinator: "all")
    Rule.create!(name: "#{outcome} #{priority}", outcome: outcome, priority: priority,
                 conditions: { combinator: combinator, conditions: conditions })
  end

  def applicant(**attrs)
    Applicant.create!({ name: "Test", email: "t#{SecureRandom.hex(4)}@example.com" }.merge(attrs))
  end

  test "first matching rule by priority decides status" do
    rule("approved", 20, condition("credit_score", "gte", 700))
    rejecting = rule("rejected", 10, condition("age", "lt", 18))

    a = applicant(age: 16, credit_score: 800)
    assert_equal "rejected", a.status
    assert_equal rejecting, a.matched_rule
  end

  test "no matching rule leaves applicant pending" do
    rule("approved", 1, condition("credit_score", "gte", 700))
    assert_equal "pending", applicant(credit_score: 600).status
  end

  test "nested any group" do
    rule("approved", 1,
      condition("credit_score", "gte", 700),
      { combinator: "any", conditions: [ condition("employment_status", "eq", "employed"), condition("annual_income", "gte", 100_000) ] })

    assert_equal "approved", applicant(credit_score: 750, employment_status: "employed").status
    assert_equal "approved", applicant(credit_score: 750, employment_status: "retired", annual_income: 120_000).status
    assert_equal "pending", applicant(credit_score: 750, employment_status: "retired", annual_income: 20_000).status
  end

  test "string operators are case-insensitive and lists work" do
    rule("rejected", 1, condition("country", "in", %w[XX YY]))
    rule("approved", 2, condition("email", "contains", "@ACME."))

    assert_equal "rejected", applicant(country: "xx").status
    assert_equal "approved", applicant(email: "jo@acme.com").status
  end

  test "nil values never match comparisons but match blank" do
    rule("rejected", 1, condition("credit_score", "lt", 500))
    rule("pending", 2, condition("credit_score", "blank"))
    a = applicant
    assert_equal "pending", a.status
    assert_equal "pending 2", a.matched_rule.name
  end

  test "editing an applicant re-evaluates" do
    rule("approved", 1, condition("credit_score", "gte", 700))
    a = applicant(credit_score: 600)
    a.update!(credit_score: 720)
    assert_equal "approved", a.status
  end

  test "changing rules re-evaluates existing applicants in the background" do
    a = applicant(credit_score: 600)
    rule("rejected", 1, condition("credit_score", "lt", 650))

    assert_equal "pending", a.reload.status, "evaluation should not run inline"
    assert_equal 1, EvaluateApplicantsJob.jobs.size
    assert_equal "evaluation", EvaluateApplicantsJob.jobs.first["queue"]

    EvaluateApplicantsJob.drain
    assert_equal "rejected", a.reload.status
  end

  test "rapid rule edits queue a single re-evaluation until it starts" do
    3.times { |i| rule("rejected", i, condition("age", "lt", 18 + i)) }
    assert_equal 1, EvaluateApplicantsJob.jobs.size

    EvaluateApplicantsJob.drain
    Rule.first.update!(active: false)
    assert_equal 1, EvaluateApplicantsJob.jobs.size, "an edit after the run started must queue a fresh run"
  end

  test "evaluate_all only writes applicants whose decision changed" do
    rejecting = rule("rejected", 1, condition("credit_score", "lt", 600))
    low = applicant(credit_score: 500)
    mid = applicant(credit_score: 650)
    high = applicant(credit_score: 800)
    low_written_at = low.reload.updated_at

    rejecting.update!(conditions: { combinator: "all", conditions: [ condition("credit_score", "lt", 700) ] })
    rule("approved", 2, condition("credit_score", "gte", 750))

    travel 1.minute do
      changed = nil
      # One UPDATE per distinct new decision (mid → rejected, high → approved), none for low.
      assert_queries_match(/UPDATE "applicants"/, count: 2) { changed = Applicant.evaluate_all! }
      assert_equal 2, changed
    end

    assert_equal %w[rejected rejected approved], [ low, mid, high ].map { |a| a.reload.status }
    assert_equal rejecting.id, mid.matched_rule_id
    assert_equal low_written_at, low.updated_at, "unchanged applicants must not be rewritten"
    assert_operator high.updated_at, :>, low_written_at
  end

  test "evaluate_all handles more applicants than one batch" do
    rule("approved", 1, condition("age", "gte", 18))
    now = Time.current
    Applicant.insert_all!(Array.new(Applicant::EVALUATION_BATCH_SIZE + 5) { |i|
      { name: "A#{i}", email: "bulk#{i}@example.com", age: 30, status: "pending", created_at: now, updated_at: now }
    })

    assert_equal Applicant::EVALUATION_BATCH_SIZE + 5, Applicant.evaluate_all!
    assert_equal 0, Applicant.where.not(status: "approved").count
  end

  test "invalid condition trees are rejected" do
    bad = Rule.new(name: "bad", outcome: "approved", conditions: { combinator: "all", conditions: [
      condition("salary", "gt", 1), condition("age", "contains", "x"), condition("age", "gt", "abc"), condition("country", "in", [])
    ] })
    assert_not bad.valid?
    assert_equal 4, bad.errors[:conditions].size

    assert_not Rule.new(name: "empty", outcome: "approved", conditions: { combinator: "all", conditions: [] }).valid?
  end
end
