# Evaluates and validates a rule's condition tree against an applicant.
#
#   { "combinator" => "all", "conditions" => [
#       { "field" => "credit_score", "operator" => "gte", "value" => 700 },
#       { "combinator" => "any", "conditions" => [ ... ] } ] }
class ConditionTree
  COMBINATORS = %w[all any].freeze

  OPERATORS = {
    "number" => %w[eq neq gt gte lt lte present blank],
    "string" => %w[eq neq contains starts_with in not_in present blank],
    "enum"   => %w[eq neq in not_in present blank]
  }.freeze

  VALUELESS_OPERATORS = %w[present blank].freeze
  LIST_OPERATORS = %w[in not_in].freeze

  def initialize(tree)
    @tree = (tree || {}).deep_stringify_keys
  end

  def matches?(applicant)
    group_matches?(@tree, applicant)
  end

  def errors
    [].tap { |errors| validate_group(@tree, errors, "root") }
  end

  private
    def group_matches?(group, applicant)
      children = Array(group["conditions"])
      return false if children.empty?

      results = children.lazy.map { |node| node_matches?(node, applicant) }
      group["combinator"] == "any" ? results.any? : results.all?
    end

    def node_matches?(node, applicant)
      node.key?("combinator") ? group_matches?(node, applicant) : condition_matches?(node, applicant)
    end

    def condition_matches?(condition, applicant)
      field = Applicant::FIELDS.fetch(condition["field"])
      actual = applicant.public_send(condition["field"])
      operator = condition["operator"]
      expected = condition["value"]

      return actual.present? if operator == "present"
      return actual.blank? if operator == "blank"
      return false if actual.nil?

      if field[:type] == "number"
        compare_numbers(actual.to_d, operator, BigDecimal(expected.to_s))
      else
        compare_strings(actual.to_s.downcase, operator, expected)
      end
    end

    def compare_numbers(actual, operator, expected)
      case operator
      when "eq"  then actual == expected
      when "neq" then actual != expected
      when "gt"  then actual > expected
      when "gte" then actual >= expected
      when "lt"  then actual < expected
      when "lte" then actual <= expected
      end
    end

    def compare_strings(actual, operator, expected)
      list = Array(expected).map { |v| v.to_s.downcase }
      expected = expected.to_s.downcase unless LIST_OPERATORS.include?(operator)

      case operator
      when "eq"          then actual == expected
      when "neq"         then actual != expected
      when "contains"    then actual.include?(expected)
      when "starts_with" then actual.start_with?(expected)
      when "in"          then list.include?(actual)
      when "not_in"      then list.exclude?(actual)
      end
    end

    def validate_group(group, errors, path)
      return errors << "#{path} must be a group" unless group.is_a?(Hash)
      errors << "#{path} combinator must be one of #{COMBINATORS.join(', ')}" unless COMBINATORS.include?(group["combinator"])

      children = group["conditions"]
      return errors << "#{path} must have at least one condition" unless children.is_a?(Array) && children.any?

      children.each_with_index do |node, i|
        child_path = "#{path}.#{i + 1}"
        if node.is_a?(Hash) && node.key?("combinator")
          validate_group(node, errors, child_path)
        else
          validate_condition(node, errors, child_path)
        end
      end
    end

    def validate_condition(condition, errors, path)
      return errors << "#{path} must be a condition" unless condition.is_a?(Hash)

      field = Applicant::FIELDS[condition["field"]]
      return errors << "#{path} has unknown field #{condition['field'].inspect}" unless field

      operator = condition["operator"]
      unless OPERATORS[field[:type]].include?(operator)
        return errors << "#{path} operator #{operator.inspect} is not valid for #{condition['field']}"
      end
      return if VALUELESS_OPERATORS.include?(operator)

      value = condition["value"]
      if LIST_OPERATORS.include?(operator)
        errors << "#{path} needs at least one value" unless value.is_a?(Array) && value.any?
      elsif value.blank?
        errors << "#{path} needs a value"
      elsif field[:type] == "number" && !numeric?(value)
        errors << "#{path} value must be a number"
      end
    end

    def numeric?(value)
      BigDecimal(value.to_s)
      true
    rescue ArgumentError
      false
    end
end
