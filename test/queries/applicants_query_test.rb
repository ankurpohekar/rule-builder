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

  test "after a cursor continues where the previous page ended, even through equal timestamps" do
    same_time = 5.days.ago
    tied = 3.times.map { |i| Applicant.create!(name: "Tied #{i}", email: "tied#{i}@example.com", created_at: same_time) }

    seen = []
    after = nil
    loop do
      page = ApplicantsQuery.call(after: after).limit(2).to_a
      break if page.empty?
      seen.concat(page)
      after = [ page.last.created_at, page.last.id ]
    end

    assert_equal ApplicantsQuery.call.map(&:id), seen.map(&:id)
    assert_equal tied.map(&:id).sort.reverse, seen.last(3).map(&:id) # ties broken by id, newest first
  end

  test "cursors round-trip and reject anything malformed" do
    created_at = Time.zone.parse("2026-10-30 10:15:30.123456")
    decoded = ApplicantsQuery::Cursor.decode(ApplicantsQuery::Cursor.encode(created_at, 42))
    assert_equal [ created_at, 42 ], decoded
    assert_equal created_at.usec, decoded.first.usec # Postgres keeps microseconds, so the cursor must too
    assert_nil ApplicantsQuery::Cursor.decode("")

    [ "not base64!", Base64.urlsafe_encode64("garbage"), Base64.urlsafe_encode64("2026-10-30T10:15:30Z,abc") ].each do |cursor|
      assert_raises(ApplicantsQuery::Cursor::Invalid) { ApplicantsQuery::Cursor.decode(cursor) }
    end
  end
end
