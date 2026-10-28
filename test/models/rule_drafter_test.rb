require "test_helper"

class RuleDrafterTest < ActiveSupport::TestCase
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
    name: "Reject minors", description: "Applicants under 18 are rejected.", outcome: "rejected",
    conditions: { combinator: "all", conditions: [ { field: "age", operator: "lt", value: 18 } ] }
  }.to_json

  test "returns an unsaved, valid rule from the model's JSON" do
    client = FakeClient.new("```json\n#{VALID}\n```")
    rule = RuleDrafter.new(client: client).draft("reject anyone under 18")

    assert rule.new_record?
    assert_equal "rejected", rule.outcome
    assert_equal "age", rule.conditions.dig("conditions", 0, "field")
    assert_equal 1, client.requests.size
    assert_equal "reject anyone under 18", client.requests.first[:messages].first[:content]
  end

  test "sends validation errors back and accepts the corrected rule" do
    invalid = { name: "Bad", outcome: "approved",
                conditions: { combinator: "all", conditions: [ { field: "salary", operator: "gt", value: 1 } ] } }.to_json
    client = FakeClient.new(invalid, VALID)

    rule = RuleDrafter.new(client: client).draft("approve high earners")
    assert_equal "Reject minors", rule.name

    retry_messages = client.requests.last[:messages]
    assert_equal %w[user assistant user], retry_messages.map { |m| m[:role] }
    assert_match(/unknown field "salary"/, retry_messages.last[:content])
  end

  test "gives up after the last attempt with the remaining problems" do
    client = FakeClient.new("not json", "still not json")
    error = assert_raises(RuleDrafter::Error) { RuleDrafter.new(client: client).draft("anything") }

    assert_equal [ "Reply was not valid JSON" ], error.problems
    assert_equal RuleDrafter::MAX_ATTEMPTS, client.requests.size
  end

  test "a description the fields can't express is reported without retrying" do
    client = FakeClient.new({ error: "There is no homeownership field" }.to_json)
    error = assert_raises(RuleDrafter::Error) { RuleDrafter.new(client: client).draft("approve homeowners") }

    assert_equal [ "There is no homeownership field" ], error.problems
    assert_equal 1, client.requests.size
  end

  test "a refusal is reported without retrying" do
    client = FakeClient.new(Response.new([], :refusal))
    assert_raises(RuleDrafter::Error) { RuleDrafter.new(client: client).draft("anything") }
    assert_equal 1, client.requests.size
  end

  test "blank descriptions never reach the model" do
    client = FakeClient.new
    assert_raises(RuleDrafter::Error) { RuleDrafter.new(client: client).draft("   ") }
    assert_empty client.requests
  end

  test "system prompt lists every field and outcome" do
    prompt = RuleDrafter.system_prompt
    Applicant::FIELDS.each_key { |field| assert_includes prompt, "- #{field} (" }
    Rule::OUTCOMES.each { |outcome| assert_includes prompt, outcome }
    assert_includes prompt, "self_employed"
  end
end
