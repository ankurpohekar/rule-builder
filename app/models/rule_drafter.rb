# Turns a plain-English description into an unsaved Rule using Claude.
#
#   RuleDrafter.new.draft("reject anyone under 18 or with a credit score below 550")
#   # => #<Rule name: "Reject minors and poor credit", outcome: "rejected", ...> (not persisted)
#
# The model's JSON goes through the same validations as a hand-built rule. If it fails,
# the errors are sent back so the model can correct itself, up to MAX_ATTEMPTS in total.
class RuleDrafter
  class Error < StandardError
    attr_reader :problems

    def initialize(problems)
      @problems = Array(problems)
      super(@problems.join("; "))
    end
  end

  MODEL = :"claude-opus-5-5"
  MAX_ATTEMPTS = 2
  MAX_DESCRIPTION_LENGTH = 2_000

  # A nil key makes the SDK fall back to ENV["ANTHROPIC_API_KEY"].
  def initialize(client: Anthropic::Client.new(api_key: Rails.application.credentials.anthropic_api_key))
    @client = client
  end

  def draft(description)
    description = description.to_s.strip
    raise Error, "Describe the rule you want" if description.blank?
    raise Error, "Description is too long (max #{MAX_DESCRIPTION_LENGTH} characters)" if description.length > MAX_DESCRIPTION_LENGTH

    messages = [ { role: "user", content: description } ]
    problems = []

    MAX_ATTEMPTS.times do
      response = request(messages)
      raise Error, "Claude declined to draft this rule" if response.stop_reason == :refusal

      rule, problems = parse(response)
      return rule if problems.empty?
      raise Error, problems if rule == :unsupported

      # Append-only: keep the full assistant turn (thinking blocks included) and add the feedback.
      messages << { role: "assistant", content: response.content.map(&:to_h) }
      messages << { role: "user", content: "That rule is invalid:\n#{problems.join("\n")}\nReply with the corrected JSON only." }
    end

    raise Error, problems
  end

  def self.system_prompt
    fields = Applicant::FIELDS.map do |key, field|
      type = field[:options] ? "#{field[:type]}: #{field[:options].join(', ')}" : field[:type]
      "- #{key} (#{type}); operators: #{ConditionTree::OPERATORS[field[:type]].join(', ')}"
    end

    <<~PROMPT
      You turn a plain-English description of a loan-applicant screening rule into JSON for a rule engine.

      Reply with one JSON object and nothing else:
      {"name": "<short title>", "description": "<one sentence>", "outcome": "<#{Rule::OUTCOMES.join('|')}>", "conditions": <group>}

      A group is {"combinator": "all" or "any", "conditions": [<condition or group>, ...]} with at least one entry.
      "all" means every entry must match (AND); "any" means at least one must match (OR). Groups may nest.
      A condition is {"field": "<field>", "operator": "<operator>", "value": <value>}.

      Fields:
      #{fields.join("\n")}

      Operators: eq (equals), neq (not equal), gt, gte, lt, lte, contains, starts_with,
      in / not_in (value is a JSON array), present / blank (omit "value").
      Number values are plain JSON numbers (100000, not "100k"). Country values are ISO 3166-1 alpha-2 codes such as "US" or "IN".
      Enum values must be one of the listed options.

      If the description is ambiguous, choose the most reasonable reading and state the assumption in "description".
      These rules decide real applications, so never stand in another field for one that does not exist: a proxy
      would match the wrong people. If any part of the description needs data the fields above cannot express,
      reply instead with {"error": "<what cannot be expressed and which fields are available>"}.
    PROMPT
  end

  private
    def request(messages)
      @client.beta.messages.create(
        model: MODEL,
        max_tokens: 16_000,
        output_config: { effort: :medium },
        system_: [ { type: "text", text: self.class.system_prompt, cache_control: { type: "ephemeral" } } ],
        messages: messages,
        # Retry on Anthropic's recommended model if a safety classifier declines the request.
        fallbacks: :default,
        betas: [ "server-side-fallback-2026-07-01" ]
      )
    end

    # Returns [rule, problems]; problems is empty when the rule is valid. The rule is
    # :unsupported when the model says the description can't be expressed (no retry).
    def parse(response)
      text = response.content.select { |block| block.type == :text }.map(&:text).join
      attrs = JSON.parse(text[/\{.*\}/m].to_s)
      return [ nil, [ "Reply must be a JSON object" ] ] unless attrs.is_a?(Hash)
      return [ :unsupported, [ attrs["error"].to_s ] ] if attrs["error"].present?

      rule = Rule.new(attrs.slice("name", "description", "outcome", "conditions").merge(active: true))
      [ rule, rule.valid? ? [] : rule.errors.full_messages ]
    rescue JSON::ParserError
      [ nil, [ "Reply was not valid JSON" ] ]
    end
end
