# Idempotency-Key support (the Stripe pattern, standardized in IETF
# draft-ietf-httpapi-idempotency-key-header). A client sends a unique key per logical
# operation; retries with the same key and body get the original response instead of
# running the action twice.
#
#   class Api::ApplicantsController < ApplicationController
#     include IdempotentRequest
#     idempotent only: :create
#   end
#
# Responses: original response replayed with `Idempotent-Replayed: true`; 409 while the
# first request is still running; 422 if the key is reused with a different body;
# 400 for a malformed key. Requests without the header behave as before.
module IdempotentRequest
  extend ActiveSupport::Concern

  HEADER = "Idempotency-Key"
  MAX_KEY_LENGTH = 255

  class_methods do
    def idempotent(**options)
      around_action :with_idempotency_key, **options
    end
  end

  private
    def with_idempotency_key(&action)
      key = request.headers[HEADER]
      return yield if key.nil?
      unless key.length.between?(1, MAX_KEY_LENGTH)
        return render json: { error: "#{HEADER} must be 1-#{MAX_KEY_LENGTH} characters" }, status: :bad_request
      end

      record, outcome = IdempotencyKey.claim(
        key: key, request_method: request.method, request_path: request.path, fingerprint: request_fingerprint
      )

      case outcome
      when :claimed     then run_and_store(record, &action)
      when :replay      then replay(record)
      when :in_progress then render json: { error: "A request with this #{HEADER} is still being processed" }, status: :conflict
      when :mismatch    then render json: { error: "#{HEADER} was already used with a different request body" }, status: :unprocessable_content
      end
    end

    # The action's writes and the stored response commit together, so a crash can never
    # leave an applicant created without its response recorded (or the reverse).
    def run_and_store(record)
      IdempotencyKey.transaction do
        yield
        record.complete!(status: response.status, body: response.body)
      end
    rescue Exception # rubocop:disable Lint/RescueException -- release the key on any failure, then re-raise
      record.release
      raise
    end

    def replay(record)
      response.headers["Idempotent-Replayed"] = "true"
      render body: record.response_body, status: record.response_status, content_type: "application/json"
    end

    # Same key + different body is a client bug, so the body is part of what we compare.
    # Keys are sorted so {"a":1,"b":2} and {"b":2,"a":1} count as the same request.
    def request_fingerprint
      Digest::SHA256.hexdigest(deep_sort(request.request_parameters).to_json)
    end

    def deep_sort(value)
      case value
      when Hash  then value.sort.to_h.transform_values { |v| deep_sort(v) }
      when Array then value.map { |v| deep_sort(v) }
      else value
      end
    end
end
