class Api::FaqQuestionsController < ApplicationController
  # Each question can cost an LLM call, and this endpoint needs no login.
  rate_limit to: 10, within: 1.minute, only: :create,
    with: -> { render json: { errors: [ "Too many questions. Wait a minute and try again." ] }, status: :too_many_requests }

  # Asks the FAQ bot. Returns the answer with the FAQ entries it came from, and logs the question.
  def create
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    reply = FaqBot.new.ask(params[:question], history: history_params)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    question = FaqQuestion.record!(params[:question].to_s.strip, reply, duration_ms: duration_ms)

    render json: { id: question.id, answer: reply.text, answered: reply.answered, sources: sources_json(reply.sources) }
  rescue FaqBot::Error => error
    render json: { errors: [ error.message ] }, status: :unprocessable_content
  rescue Anthropic::Errors::Error => error # API failures and missing credentials
    Rails.logger.error("FAQ bot failed: #{error.class}: #{error.message}")
    render json: { errors: [ "The assistant is unavailable right now. Try searching the FAQ instead." ] }, status: :bad_gateway
  end

  # Records thumbs up / down on an answer.
  def update
    question = FaqQuestion.find(params[:id])
    if question.update(feedback: params.require(:feedback))
      head :no_content
    else
      render_errors(question)
    end
  end

  private
    def history_params
      params.fetch(:history, []).map { |message| message.permit(:role, :content).to_h }
    end

    def sources_json(keys)
      keys.filter_map { |key| Faq.find(key) }.map { |item| { key: item.key, question: item.question } }
    end
end
