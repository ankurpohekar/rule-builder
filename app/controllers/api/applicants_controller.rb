class Api::ApplicantsController < ApplicationController
  include IdempotentRequest

  before_action :set_applicant, only: %i[update destroy]
  # Retried or double-submitted creates return the first response instead of a duplicate applicant.
  idempotent only: :create

  rescue_from ApplicantsQuery::Cursor::Invalid do |error|
    render json: { error: error.message }, status: :bad_request
  end

  # One page, newest first (?limit=, default 50, max 200). When there are more, the Link header
  # holds the next page's URL (rel="next", as GitHub's API does), and the body stays a plain array.
  def index
    page = ApplicantCache.page(status: params[:status], q: params[:q], after: params[:after],
                               limit: params[:limit].presence || ApplicantCache::DEFAULT_LIMIT)
    if page.next_cursor
      response.headers["Link"] = %(<#{request.path}?#{request.query_parameters.merge("after" => page.next_cursor).to_query}>; rel="next")
    end
    render json: page.applicants
  end

  def show
    render json: ApplicantCache.find(params[:id])
  end

  def create
    form = ApplicantForm.new(applicant_params)
    if form.save
      render json: serialize(form.applicant), status: :created
    else
      render_errors(form)
    end
  end

  def update
    form = ApplicantForm.new(applicant_params, applicant: @applicant)
    if form.save
      render json: serialize(form.applicant)
    else
      render_errors(form)
    end
  end

  def destroy
    @applicant.destroy!
    head :no_content
  end

  # Reads applicant details out of free text. Nothing is saved: the client fills the form
  # with the draft so a person checks it and completes any missing fields before creating it.
  def draft
    attrs = ApplicantDrafter.new.draft(params.require(:text))
    render json: attrs
  rescue ApplicantDrafter::Error => error
    render json: { errors: error.problems }, status: :unprocessable_content
  rescue Anthropic::Errors::Error => error # API failures and missing credentials
    Rails.logger.error("Applicant draft failed: #{error.class}: #{error.message}")
    render json: { errors: [ "The AI service is unavailable right now. Try again or fill in the form by hand." ] }, status: :bad_gateway
  end

  # Queues a re-run of every applicant through the current rules. If a run is already
  # waiting, it covers this request, so no new job is queued (job_id is null).
  def evaluate
    job_id = EvaluateApplicantsJob.enqueue
    render json: { job_id: job_id, queued: job_id.present? }, status: :accepted
  end

  private
    def set_applicant
      @applicant = Applicant.find(params[:id])
    end

    def applicant_params
      params.expect(applicant: %i[name email age credit_score annual_income employment_status country])
    end

    def serialize(applicant)
      applicant.as_json.merge("matched_rule" => applicant.matched_rule&.as_json(only: %i[id name outcome]))
    end
end
