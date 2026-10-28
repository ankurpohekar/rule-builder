require "test_helper"

class ApplicantsQueryTest < ActiveSupport::TestCase
  setup do
    @asha  = Applicant.create!(name: "Asha Rao", email: "asha@example.com", created_at: 3.days.ago)
    @ben   = Applicant.create!(name: "Ben Carter", email: "ben@example.com", created_at: 2.days.ago)
    @priya = Applicant.create!(name: "Priya Shah", email: "priya@shah-co.com", created_at: 1.day.ago)
    @ben.update_column(:status, "approved")
  end

  def names(relation) = relation.map(&:name)

  test "returns everyone newest first when no filters are given" do
    assert_equal [ "Priya Shah", "Ben Carter", "Asha Rao" ], names(ApplicantsQuery.call)
  end

  test "ignores blank filters" do
    assert_equal 3, ApplicantsQuery.call(status: "", q: "   ").size
  end

  test "filters by status" do
    assert_equal [ "Ben Carter" ], names(ApplicantsQuery.call(status: "approved"))
  end

  test "searches name and email" do
    assert_equal [ "Priya Shah", "Asha Rao" ], names(ApplicantsQuery.call(q: "sha"))
  end

  test "combines status and search" do
    assert_equal [ "Asha Rao" ], names(ApplicantsQuery.call(status: "pending", q: " ASHA "))
  end

  test "loads matched rules without a query per applicant" do
    rule = Rule.create!(name: "Approve all", outcome: "approved", priority: 1,
      conditions: { combinator: "all", conditions: [ { field: "email", operator: "present" } ] })
    Applicant.update_all(matched_rule_id: rule.id)

    applicants = ApplicantsQuery.call.to_a
    assert_queries_count(0) { applicants.each { |a| a.matched_rule&.name } }
  end

  test "builds on a given relation" do
    scoped = ApplicantsQuery.new(Applicant.where.not(id: @priya.id), q: "sha").call
    assert_equal [ "Asha Rao" ], names(scoped)
  end
end
