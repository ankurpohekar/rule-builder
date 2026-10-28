# Describes what the rule builder UI can offer: fields, operators and outcomes.
class Api::SchemaController < ApplicationController
  def show
    render json: {
      fields: Applicant::FIELDS.map { |key, field| { key: key, **field, operators: ConditionTree::OPERATORS[field[:type]] } },
      outcomes: Rule::OUTCOMES,
      statuses: Applicant::STATUSES
    }
  end
end
