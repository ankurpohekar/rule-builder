require "test_helper"

# Lets a test make applicant creation blow up mid-request.
module ExplodingApplicantForm
  mattr_accessor :enabled, default: false

  def save
    raise "database went away" if ExplodingApplicantForm.enabled
    super
  end
end
ApplicantForm.prepend(ExplodingApplicantForm)

class IdempotencyTest < ActionDispatch::IntegrationTest
  BODY = { applicant: { name: "Ana Diaz", email: "ana@example.com", credit_score: 720 } }.freeze

  def create_applicant(key:, body: BODY)
    headers = key ? { "Idempotency-Key" => key } : {}
    post "/api/applicants", params: body, headers: headers, as: :json
  end

  def replayed? = response.headers["Idempotent-Replayed"] == "true"

  teardown { ExplodingApplicantForm.enabled = false }

  test "a retry with the same key returns the original response without creating a duplicate" do
    create_applicant(key: "key-1")
    assert_response :created
    first_body = response.body
    assert_not replayed?

    create_applicant(key: "key-1")
    assert_response :created
    assert replayed?
    assert_equal first_body, response.body
    assert_equal 1, Applicant.where(email: "ana@example.com").count
  end

  test "the same body with JSON keys in a different order counts as the same request" do
    create_applicant(key: "key-1")
    post "/api/applicants", headers: { "Idempotency-Key" => "key-1", "CONTENT_TYPE" => "application/json" },
      params: '{"applicant":{"credit_score":720,"email":"ana@example.com","name":"Ana Diaz"}}'
    assert_response :created
    assert replayed?
  end

  test "reusing a key with a different body is rejected" do
    create_applicant(key: "key-1")
    create_applicant(key: "key-1", body: { applicant: BODY[:applicant].merge(name: "Someone Else") })
    assert_response :unprocessable_content
    assert_match "different request body", response.parsed_body["error"]
  end

  test "a retry while the original is still running gets 409" do
    create_applicant(key: "key-1")
    IdempotencyKey.last.update!(completed_at: nil, locked_at: Time.current)

    create_applicant(key: "key-1")
    assert_response :conflict
  end

  test "a retry can take over a key whose original request died" do
    create_applicant(key: "key-1")
    Applicant.delete_all # as if the original's work had rolled back
    IdempotencyKey.last.update!(completed_at: nil, locked_at: 2.minutes.ago)

    create_applicant(key: "key-1")
    assert_response :created
    assert_not replayed?
    assert_equal 1, Applicant.count
  end

  test "validation failures are replayed too" do
    invalid = { applicant: { name: "Ana", email: "not-an-email" } }
    create_applicant(key: "key-1", body: invalid)
    assert_response :unprocessable_content
    create_applicant(key: "key-1", body: invalid)
    assert_response :unprocessable_content
    assert replayed?
  end

  test "if the action raises, the key is released so a retry runs again" do
    ExplodingApplicantForm.enabled = true
    # The test environment re-raises instead of rendering a 500.
    assert_raises(RuntimeError) { create_applicant(key: "key-1") }
    assert_equal 0, IdempotencyKey.count

    ExplodingApplicantForm.enabled = false
    create_applicant(key: "key-1")
    assert_response :created
    assert_not replayed?
  end

  test "expired keys are treated as unused" do
    create_applicant(key: "key-1")
    Applicant.delete_all
    IdempotencyKey.last.update!(created_at: 25.hours.ago)

    create_applicant(key: "key-1")
    assert_response :created
    assert_not replayed?
  end

  test "requests without the header behave as before" do
    create_applicant(key: nil)
    assert_response :created
    assert_equal 0, IdempotencyKey.count
  end

  test "malformed keys are rejected" do
    [ "", "x" * 256 ].each do |key|
      create_applicant(key: key)
      assert_response :bad_request
    end
    assert_equal 0, Applicant.count
  end

  test "purge_expired removes only keys past the TTL" do
    create_applicant(key: "old")
    IdempotencyKey.last.update!(created_at: 25.hours.ago)
    create_applicant(key: "new", body: { applicant: BODY[:applicant].merge(email: "new@example.com") })

    assert_equal 1, IdempotencyKey.purge_expired
    assert_equal [ "new" ], IdempotencyKey.pluck(:key)
  end
end
