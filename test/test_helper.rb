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

# Stands in for the local embedding model (which is a 130 MB download): hashes each word into
# one of the 384 dimensions, so texts sharing words come out similar. Deterministic and instant.
class HashingEmbedder
  attr_reader :calls

  def initialize
    @calls = []
  end

  def embed_documents(texts)
    @calls << texts
    texts.map { |text| vector(text) }
  end

  def embed_query(text) = vector(text)

  private
    def vector(text)
      values = Array.new(Embedder::DIMENSIONS, 0.0)
      text.downcase.scan(/[a-z0-9]+/).each { |word| values[Zlib.crc32(word) % Embedder::DIMENSIONS] += 1 }
      norm = Math.sqrt(values.sum { |v| v * v })
      norm.zero? ? values : values.map { |v| v / norm }
    end
end
Embedder.default = HashingEmbedder.new

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
