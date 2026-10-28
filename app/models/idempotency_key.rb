# One row per Idempotency-Key used on an endpoint. Lifecycle:
#   claimed (locked_at set) → completed (response stored) → expired after TTL
class IdempotencyKey < ApplicationRecord
  # How long a stored response can be replayed. Older keys count as unused.
  TTL = 24.hours
  # A key locked longer than this belongs to a request that died mid-flight; a retry may take it over.
  LOCK_TIMEOUT = 1.minute

  scope :expired, -> { where(created_at: ...TTL.ago) }

  # Decides what to do with a request carrying `key`. Returns [record, outcome]:
  #   :claimed     - this request owns the key and should run the action
  #   :replay      - the same request already completed; send back its stored response
  #   :in_progress - the same request is running right now
  #   :mismatch    - the key was already used with a different request body
  def self.claim(key:, request_method:, request_path:, fingerprint:)
    identity = { key: key, request_method: request_method, request_path: request_path }
    now = Time.current

    # INSERT ... ON CONFLICT DO NOTHING: of any number of concurrent requests, exactly one inserts.
    inserted = insert(identity.merge(request_fingerprint: fingerprint, locked_at: now),
                      unique_by: :index_idempotency_keys_uniqueness, returning: :id)
    return [ find(inserted.first["id"]), :claimed ] if inserted.any?

    existing = find_by(identity)
    return claim(key:, request_method:, request_path:, fingerprint:) if existing.nil? # deleted meanwhile

    if existing.created_at < TTL.ago
      where(id: existing.id).delete_all
      return claim(key:, request_method:, request_path:, fingerprint:)
    end

    return [ existing, :mismatch ] if existing.request_fingerprint != fingerprint
    return [ existing, :replay ] if existing.completed_at

    # Take over a stale lock only if nobody else took it first (compare-and-set on locked_at).
    if existing.locked_at < LOCK_TIMEOUT.ago &&
        where(id: existing.id, completed_at: nil, locked_at: existing.locked_at).update_all(locked_at: now) == 1
      return [ existing.reload, :claimed ]
    end

    [ existing, :in_progress ]
  end

  def self.purge_expired
    expired.delete_all
  end

  def complete!(status:, body:)
    update!(response_status: status, response_body: body, completed_at: Time.current, locked_at: nil)
  end

  # Gives the key up so a retry can run the action again (used when the action raised).
  def release
    self.class.where(id: id, completed_at: nil).delete_all
  end
end
