require "test_helper"

class ApplicantCacheTest < ActiveSupport::TestCase
  setup do
    ApplicantCache.store = ActiveSupport::Cache::MemoryStore.new
    @rule = Rule.create!(name: "Approve good credit", outcome: "approved", priority: 1,
      conditions: { combinator: "all", conditions: [ { field: "credit_score", operator: "gte", value: 700 } ] })
    @asha = Applicant.create!(name: "Asha Rao", email: "asha@example.com", credit_score: 720, created_at: 2.days.ago)
    @ben  = Applicant.create!(name: "Ben Carter", email: "ben@example.com", credit_score: 600, created_at: 1.day.ago)
  end

  teardown { ApplicantCache.store = nil }

  def names(page) = page.applicants.map { |a| a["name"] }

  test "find serves a cached applicant without touching the database" do
    first = ApplicantCache.find(@asha.id)
    assert_equal "Asha Rao", first["name"]
    assert_equal({ "id" => @rule.id, "name" => "Approve good credit", "outcome" => "approved" }, first["matched_rule"])

    assert_no_queries { assert_equal first, ApplicantCache.find(@asha.id.to_s) }
  end

  test "find raises not found for missing or malformed ids" do
    assert_raises(ActiveRecord::RecordNotFound) { ApplicantCache.find(0) }
    assert_raises(ActiveRecord::RecordNotFound) { ApplicantCache.find("abc") }
  end

  test "a repeated page is served from the cache" do
    assert_equal [ "Ben Carter", "Asha Rao" ], names(ApplicantCache.page)
    assert_no_queries { assert_equal [ "Ben Carter", "Asha Rao" ], names(ApplicantCache.page) }
  end

  test "updating an applicant refreshes it without throwing away cached pages" do
    ApplicantCache.page
    @asha.update!(age: 31)

    # The page's id list is still cached; only Asha's record is loaded again.
    assert_queries_count(1) { assert_equal 31, ApplicantCache.page.applicants.last["age"] }
    assert_equal 31, ApplicantCache.find(@asha.id)["age"]
  end

  test "changes that move applicants between pages start new pages" do
    assert_equal [ "Asha Rao" ], names(ApplicantCache.page(status: "approved"))

    @ben.update!(credit_score: 710) # now approved
    assert_equal [ "Ben Carter", "Asha Rao" ], names(ApplicantCache.page(status: "approved"))

    Applicant.create!(name: "Cara Diaz", email: "cara@example.com")
    assert_equal "Cara Diaz", names(ApplicantCache.page).first

    @asha.destroy!
    assert_equal [ "Cara Diaz", "Ben Carter" ], names(ApplicantCache.page)
    assert_raises(ActiveRecord::RecordNotFound) { ApplicantCache.find(@asha.id) }
  end

  test "renaming a rule shows up on cached applicants" do
    ApplicantCache.find(@asha.id)
    @rule.update!(name: "Good credit")
    assert_equal "Good credit", ApplicantCache.find(@asha.id).dig("matched_rule", "name")
  end

  test "bulk re-evaluation expires the applicants it changed" do
    ApplicantCache.page(status: "approved")
    ApplicantCache.find(@asha.id)
    @rule.update_column(:conditions, { combinator: "all", conditions: [ { field: "credit_score", operator: "gte", value: 800 } ] })

    Applicant.evaluate_all! # update_all, no callbacks

    assert_equal "pending", ApplicantCache.find(@asha.id)["status"]
    assert_empty ApplicantCache.page(status: "approved").applicants
  end

  test "search terms that differ only in case and spacing share a page" do
    ApplicantCache.page(q: "Asha")
    assert_no_queries { assert_equal [ "Asha Rao" ], names(ApplicantCache.page(q: "  asha ")) }
  end

  test "pages through with next_cursor" do
    first = ApplicantCache.page(limit: 1)
    assert_equal [ "Ben Carter" ], names(first)

    second = ApplicantCache.page(limit: 1, after: first.next_cursor)
    assert_equal [ "Asha Rao" ], names(second)
    assert_nil second.next_cursor
  end

  test "an applicant deleted after its page was cached is left out" do
    ApplicantCache.page
    @asha.delete # no callbacks, as with bulk SQL

    ApplicantCache.expire(@asha.id)
    assert_equal [ "Ben Carter" ], names(ApplicantCache.page)
  end

  test "without a cache store everything still comes from the database" do
    ApplicantCache.store = ActiveSupport::Cache::NullStore.new
    assert_equal [ "Ben Carter", "Asha Rao" ], names(ApplicantCache.page)
    assert_equal "Asha Rao", ApplicantCache.find(@asha.id)["name"]
  end
end
