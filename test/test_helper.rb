ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Sidekiq jobs are pushed to in-memory arrays instead of Redis; tests drain them explicitly.
Sidekiq.testing!(:fake)

# The job's "already queued" flag lives in Redis; keep tests Redis-free with an in-process stand-in.
module InMemoryPendingFlag
  def claim_pending
    return false if @pending
    @pending = true
  end

  def release_pending
    @pending = false
  end
end
EvaluateApplicantsJob.singleton_class.prepend(InMemoryPendingFlag)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    setup do
      Sidekiq::Job.clear_all
      EvaluateApplicantsJob.release_pending
    end

    # Add more helper methods to be used by all tests here...
  end
end
