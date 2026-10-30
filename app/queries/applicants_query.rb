# Builds the applicant list from request filters. Blank filters are ignored.
# Returns a relation, so callers can still chain onto it (paginate, count, etc.).
#
#   ApplicantsQuery.call(status: "pending", q: "asha")
#   ApplicantsQuery.call(after: ApplicantsQuery::Cursor.decode(params[:after])).limit(50)
#
# Ordered newest first with id as the tie-breaker, so the order is total and stable: that is
# what lets `after:` (keyset pagination) continue exactly where the previous page ended.
class ApplicantsQuery
  # A cursor names the last row of a page as (created_at, id). It is opaque to clients: they
  # pass back what they were given.
  module Cursor
    class Invalid < StandardError; end

    def self.encode(created_at, id)
      Base64.urlsafe_encode64("#{created_at.utc.iso8601(6)},#{id}", padding: false)
    end

    # Returns [created_at, id], or nil for a blank cursor.
    def self.decode(cursor)
      return if cursor.blank?
      time, id = Base64.urlsafe_decode64(cursor).split(",", 2)
      [ Time.iso8601(time), Integer(id, 10) ]
    rescue ArgumentError, TypeError
      raise Invalid, "Invalid cursor"
    end
  end

  def self.call(...) = new(...).call

  def initialize(relation = Applicant.all, status: nil, q: nil, after: nil)
    @relation = relation
    @status = status.presence
    @q = q.to_s.strip.presence
    @after = after
  end

  def call
    scope = @relation.includes(:matched_rule).order(created_at: :desc, id: :desc)
    scope = scope.where(status: @status) if @status
    scope = scope.search(@q) if @q
    # A row comparison, so Postgres can use the (created_at, id) indexes as one range.
    scope = scope.where("(applicants.created_at, applicants.id) < (?, ?)", *@after) if @after
    scope
  end
end
