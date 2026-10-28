# Builds the applicant list from request filters. Blank filters are ignored.
# Returns a relation, so callers can still chain onto it (paginate, count, etc.).
#
#   ApplicantsQuery.call(status: "pending", q: "asha")
class ApplicantsQuery
  def self.call(...) = new(...).call

  def initialize(relation = Applicant.all, status: nil, q: nil)
    @relation = relation
    @status = status.presence
    @q = q.to_s.strip.presence
  end

  def call
    scope = @relation.includes(:matched_rule).order(created_at: :desc)
    scope = scope.where(status: @status) if @status
    scope = scope.search(@q) if @q
    scope
  end
end
