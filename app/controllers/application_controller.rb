class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound do |error|
    render json: { error: error.message }, status: :not_found
  end

  private
    def render_errors(record)
      render json: { errors: record.errors.full_messages }, status: :unprocessable_content
    end
end
