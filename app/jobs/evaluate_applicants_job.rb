# Re-runs every applicant through the current rules. Runs on the single-threaded
# "evaluation" capsule, so runs never overlap and the last one always sees the newest rules.
class EvaluateApplicantsJob
  include Sidekiq::Job
  sidekiq_options queue: "evaluation", retry: 3

  # Set while a run is queued but not yet started. The expiry only matters if a queued job
  # is lost; expiring early is harmless (at worst one redundant run).
  PENDING_KEY = "evaluate_applicants:pending"
  PENDING_TTL = 5.minutes.to_i

  # Queues a run unless one is already waiting. A waiting run loads the rules when it
  # starts, so it already covers this change. Returns the job id, or nil if coalesced.
  def self.enqueue
    perform_async if claim_pending
  end

  def self.claim_pending
    Sidekiq.redis { |redis| redis.call("SET", PENDING_KEY, "1", "NX", "EX", PENDING_TTL) } == "OK"
  end

  def self.release_pending
    Sidekiq.redis { |redis| redis.call("DEL", PENDING_KEY) }
  end

  def perform
    # Release before loading rules: any edit committed from here on queues a fresh run,
    # and any edit committed earlier is visible to the load below.
    self.class.release_pending
    changed = Applicant.evaluate_all!
    logger.info "Re-evaluated applicants: #{changed} changed"
  end
end
