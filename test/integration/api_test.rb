require "test_helper"

class ApiTest < ActionDispatch::IntegrationTest
  test "create a rule and an applicant through the API" do
    post "/api/rules", as: :json, params: { rule: {
      name: "Approve good credit", outcome: "approved", priority: 1, active: true,
      conditions: { combinator: "all", conditions: [ { field: "credit_score", operator: "gte", value: 700 } ] }
    } }
    assert_response :created

    post "/api/applicants", as: :json, params: { applicant: { name: "Ana", email: "ana@example.com", credit_score: 710 } }
    assert_response :created
    body = response.parsed_body
    assert_equal "approved", body["status"]
    assert_equal "Approve good credit", body.dig("matched_rule", "name")

    get "/api/applicants", params: { status: "approved" }
    assert_equal 1, response.parsed_body.size
  end

  test "search by name or email combined with status filter" do
    Applicant.create!(name: "Priya Shah", email: "priya@example.com")
    Applicant.create!(name: "Sam Lee", email: "sam@shah-co.com")
    Applicant.create!(name: "Ravi Kumar", email: "ravi@example.com")

    get "/api/applicants", params: { q: "SHAH" }
    assert_equal [ "Priya Shah", "Sam Lee" ], response.parsed_body.map { |a| a["name"] }.sort

    get "/api/applicants", params: { q: "shah", status: "approved" }
    assert_empty response.parsed_body

    get "/api/applicants", params: { q: "100%" }
    assert_empty response.parsed_body
  end

  test "search matches substrings anywhere in name or email" do
    Applicant.create!(name: "Priya Shah", email: "priya@example.com")
    Applicant.create!(name: "Sam Lee", email: "sam@shah-co.com")

    { "riy" => [ "Priya Shah" ], "AH-C" => [ "Sam Lee" ], "@ex" => [ "Priya Shah" ], "zzz" => [] }.each do |q, names|
      assert_search q, names
    end
  end

  test "1-2 character searches match the start of name or email only" do
    Applicant.create!(name: "Priya Shah", email: "priya@example.com")
    Applicant.create!(name: "Sam Lee", email: "sam@shah-co.com")
    Applicant.create!(name: "Ravi Kumar", email: "kumar.r@example.com")

    { "PR" => [ "Priya Shah" ], "s" => [ "Sam Lee" ], "ku" => [ "Ravi Kumar" ], # name or email prefix
      "ah" => [], "@" => [], "%" => [] }.each do |q, names|                     # inside a value doesn't count
      assert_search q, names
    end
  end

  test "searches can use the trigram and prefix indexes" do
    { "shah" => %w[index_applicants_on_name_trgm index_applicants_on_email_trgm],
      "sh"   => %w[index_applicants_on_lower_name_prefix index_applicants_on_lower_email_prefix] }.each do |q, indexes|
      plan = ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("SET LOCAL enable_seqscan = off")
        ActiveRecord::Base.connection.select_values("EXPLAIN #{Applicant.search(q).to_sql}").join("\n")
      end
      indexes.each { |index| assert_includes plan, index, "q=#{q.inspect}" }
    end
  end

  test "re-evaluate endpoint queues one background job and coalesces repeats" do
    post "/api/applicants/evaluate"
    assert_response :accepted
    assert response.parsed_body["queued"]
    assert_equal [ response.parsed_body["job_id"] ], EvaluateApplicantsJob.jobs.map { |j| j["jid"] }

    post "/api/applicants/evaluate"
    assert_response :accepted
    assert_not response.parsed_body["queued"]
    assert_equal 1, EvaluateApplicantsJob.jobs.size
  end

  test "creating and updating applicants goes through the form" do
    post "/api/applicants", as: :json, params: { applicant: { name: " Ana  Diaz ", email: " ANA@Example.com ", age: "29" } }
    assert_response :created
    assert_equal [ "Ana Diaz", "ana@example.com", 29 ], response.parsed_body.values_at("name", "email", "age")

    id = response.parsed_body["id"]
    patch "/api/applicants/#{id}", as: :json, params: { applicant: { credit_score: "abc", country: "spain" } }
    assert_response :unprocessable_content
    assert_equal [ "Country must be a 2-letter code like US", "Credit score is not a number" ], response.parsed_body["errors"].sort
  end

  test "invalid rule returns errors" do
    post "/api/rules", as: :json, params: { rule: { name: "x", outcome: "approved", conditions: { combinator: "all", conditions: [] } } }
    assert_response :unprocessable_content
    assert response.parsed_body["errors"].any?
  end

  test "schema lists fields with operators" do
    get "/api/schema"
    field = response.parsed_body["fields"].find { |f| f["key"] == "credit_score" }
    assert_includes field["operators"], "gte"
  end

  private
    def assert_search(q, names)
      get "/api/applicants", params: { q: q }
      assert_equal names, response.parsed_body.map { |a| a["name"] }.sort, "q=#{q.inspect}"
    end
end
