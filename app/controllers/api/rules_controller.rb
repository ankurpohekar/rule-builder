class Api::RulesController < ApplicationController
  before_action :set_rule, only: %i[show update destroy]

  def index
    render json: Rule.by_priority
  end

  def show
    render json: @rule
  end

  def create
    rule = Rule.new(rule_params)
    if rule.save
      render json: rule, status: :created
    else
      render_errors(rule)
    end
  end

  def update
    if @rule.update(rule_params)
      render json: @rule
    else
      render_errors(@rule)
    end
  end

  def destroy
    @rule.destroy!
    head :no_content
  end

  # Drafts a rule from a plain-English description. Nothing is saved: the client shows
  # the draft in the editor so a person reviews it before creating it.
  def draft
    rule = RuleDrafter.new.draft(params.require(:description))
    render json: rule.slice(:name, :description, :outcome, :priority, :active, :conditions)
  rescue RuleDrafter::Error => error
    render json: { errors: error.problems }, status: :unprocessable_content
  rescue Anthropic::Errors::Error => error # API failures and missing credentials
    Rails.logger.error("Rule draft failed: #{error.class}: #{error.message}")
    render json: { errors: [ "The AI service is unavailable right now. Try again or build the rule by hand." ] }, status: :bad_gateway
  end

  private
    def set_rule
      @rule = Rule.find(params[:id])
    end

    # The condition tree is free-form JSON; Rule validates its shape.
    def rule_params
      attrs = params.expect(rule: %i[name description outcome priority active])
      conditions = params.dig(:rule, :conditions)
      conditions ? attrs.merge(conditions: conditions.to_unsafe_h) : attrs
    end
end
