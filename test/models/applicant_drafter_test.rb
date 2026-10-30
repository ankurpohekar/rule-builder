require "test_helper"

class ApplicantDrafterTest < ActiveSupport::TestCase
  Block = Struct.new(:type, :text) do
    def to_h = { type: type, text: text }
  end
  Response = Struct.new(:content, :stop_reason)

  # Stands in for Anthropic::Client: replays canned replies and records each request.
  class FakeClient
    attr_reader :requests

    def initialize(*replies)
      @replies = replies
      @requests = []
    end

    def beta = self
    def messages = self

    def create(**params)
      @requests << params.merge(messages: params[:messages].dup)
      reply = @replies.shift
      reply.is_a?(Response) ? reply : Response.new([ Block.new(:text, reply) ], :end_turn)
    end
  end

  VALID = {
    name: "Priya Shah", email: "Priya@Acme.io", age: 29, credit_score: 742,
    annual_income: 85_000, employment_status: "employed", country: "in"
  }.to_json

  def draft(*replies, text: "Priya Shah, priya@acme.io, 29, salaried in India")
    client = FakeClient.new(*replies)
    [ ApplicantDrafter.new(client: client).draft(text), client ]
  end

  test "returns normalized attributes from the model's JSON without saving anything" do
    attrs, client = draft("```json\n#{VALID}\n```")

    assert_equal "priya@acme.io", attrs["email"]
    assert_equal "IN", attrs["country"]
    assert_equal 742, attrs["credit_score"]
    assert_equal 0, Applicant.count
    assert_equal 1, client.requests.size
  end

  test "details the text doesn't give stay blank and are not sent back as errors" do
    attrs, client = draft({ name: "Priya Shah", email: nil, age: nil }.to_json)

    assert_equal "Priya Shah", attrs["name"]
    assert_nil attrs["email"]
    assert_equal 1, client.requests.size
  end

  test "keys outside the form are ignored" do
    attrs, _ = draft({ name: "Priya Shah", status: "approved" }.to_json)
    assert_not attrs.key?("status")
  end

  test "sends invalid values back and accepts the corrected ones" do
    invalid = { name: "Priya Shah", credit_score: 9000, annual_income: "85k" }.to_json
    attrs, client = draft(invalid, VALID)
    assert_equal 742, attrs["credit_score"]

    retry_messages = client.requests.last[:messages]
    assert_equal %w[user assistant user], retry_messages.map { |m| m[:role] }
    assert_match "Credit score must be in 300..850", retry_messages.last[:content]
    assert_match "Annual income is not a number", retry_messages.last[:content]
  end

  test "gives up after the last attempt with the remaining problems" do
    error = assert_raises(ApplicantDrafter::Error) { draft("not json", "still not json") }
    assert_equal [ "Reply was not valid JSON" ], error.problems
  end

  test "text that describes no applicant is reported without retrying" do
    client = FakeClient.new({ error: "The text has no personal details" }.to_json)
    error = assert_raises(ApplicantDrafter::Error) { ApplicantDrafter.new(client: client).draft("hello") }

    assert_equal [ "The text has no personal details" ], error.problems
    assert_equal 1, client.requests.size
  end

  test "a refusal is reported without retrying" do
    client = FakeClient.new(Response.new([], :refusal))
    assert_raises(ApplicantDrafter::Error) { ApplicantDrafter.new(client: client).draft("anything") }
    assert_equal 1, client.requests.size
  end

  test "blank text never reaches the model" do
    client = FakeClient.new
    assert_raises(ApplicantDrafter::Error) { ApplicantDrafter.new(client: client).draft("   ") }
    assert_empty client.requests
  end

  test "system prompt lists every form field and employment status" do
    prompt = ApplicantDrafter.system_prompt
    ApplicantForm.attribute_names.each { |field| assert_includes prompt, "- #{field} (" }
    Applicant::EMPLOYMENT_STATUSES.each { |status| assert_includes prompt, status }
  end
end
