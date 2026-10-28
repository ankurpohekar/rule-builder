class Api::ApplicantsController < ApplicationController
  include IdempotentRequest

  before_action :set_applicant, only: %i[show update destroy]
  # Retried or double-submitted creates return the first response instead of a duplicate applicant.
  idempotent only: :create

  def index
    applicants = ApplicantsQuery.call(status: params[:status], q: params[:q])
    render json: applicants.map { |a| serialize(a) }
  end

  def show
    render json: serialize(@applicant)
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
