# Read-through cache for the applicants API, in Redis (Rails.cache).
#
# Three kinds of entries, so a change only throws away what it actually affects:
#
#   applicants/v1/<id>                  one applicant's attributes          RECORD_TTL
#   applicants/v1/page/<token>/<digest> the ids (and next cursor) of one    PAGE_TTL
#                                       list page for one set of filters
#   rules/v1/summaries/<token>          id => {id, name, outcome} of every  no TTL (token)
#                                       rule, for the "Decided by" column
#
# A page stores ids, not applicants: its records come from the per-applicant entries in one
# MGET, and only the misses are loaded from Postgres, in one query. Editing an applicant's
# income then refreshes that one entry, while every cached page that lists it stays valid.
#
# Invalidation:
# - An applicant write deletes its record entry (after commit, see Applicant#expire_cache).
# - Writes that can change which applicants a page lists, or their order (create, delete,
#   or a change to name, email or status), switch the page token. Old pages are then never
#   read again and Redis evicts them (allkeys-lru, plus their TTL). Deleting them one by one
#   would mean finding every cached filter combination.
# - Rule writes switch the rules token. Applicant entries don't embed rule names, so renaming
#   a rule invalidates one small entry instead of every applicant it decided.
# Tokens are random, not counters, so a token Redis evicted can't come back as an old value
# and bring stale pages back with it.
#
# Consistency: a reader that loaded a row just before a write committed can put that old row
# back after the write deleted it. TTLs bound how long that can last (RECORD_TTL), which is
# the usual trade-off for cache-aside. Bulk SQL that skips callbacks (update_all, insert_all,
# delete_all) must call expire / expire_pages! itself, as Applicant.evaluate_all! does.
#
# If Redis is down, Rails' Redis store reports the error and returns misses, so reads fall
# back to Postgres instead of failing.
class ApplicantCache
  # Bump to change the shape of cached values: new keys, and old entries just age out.
  VERSION = 1
  RECORD_TTL = 1.hour
  PAGE_TTL = 5.minutes
  # Spread expiries by up to this share of the TTL so entries written together don't all
  # expire, and hit Postgres, in the same second.
  TTL_JITTER = 0.1
  # When a hot entry expires, one request reloads it while others are served the old value
  # for up to this long, instead of all of them hitting Postgres at once (cache stampede).
  RACE_CONDITION_TTL = 10.seconds
  # Changing these can move an applicant in or out of a filtered page.
  PAGE_FIELDS = %w[name email status].freeze

  DEFAULT_LIMIT = 50
  MAX_LIMIT = 200

  TOKEN_KEYS = { pages: "applicants/v#{VERSION}/page_token", rules: "rules/v#{VERSION}/summaries_token" }.freeze

  Page = Data.define(:applicants, :next_cursor)

  class << self
    attr_writer :store # tests swap in a MemoryStore; the test environment's Rails.cache is a null store

    def store = @store || Rails.cache

    # One applicant as the API renders it. Raises ActiveRecord::RecordNotFound.
    def find(id)
      id = Integer(id.to_s, 10, exception: false) or raise ActiveRecord::RecordNotFound.new("Couldn't find Applicant with 'id'=#{id}", "Applicant")
      attributes = store.fetch(record_key(id), expires_in: jittered(RECORD_TTL), race_condition_ttl: RACE_CONDITION_TTL) do
        Applicant.find(id).as_json
      end
      with_rule(attributes, rule_summaries(tokens.fetch(:rules)))
    end

    # One page of ApplicantsQuery results, newest first. `after` is the previous page's
    # next_cursor. Raises ApplicantsQuery::Cursor::Invalid for a malformed cursor.
    def page(status: nil, q: nil, after: nil, limit: DEFAULT_LIMIT)
      status = status.presence
      q = q.to_s.squish.downcase.presence # search is case-insensitive, so "Asha" and "asha" share an entry
      cursor = ApplicantsQuery::Cursor.decode(after)
      limit = limit.to_i.clamp(1, MAX_LIMIT)
      tokens = self.tokens

      ids, next_cursor = store.fetch(page_key(tokens.fetch(:pages), status:, q:, after:, limit:),
                                     expires_in: jittered(PAGE_TTL), race_condition_ttl: RACE_CONDITION_TTL) do
        # Without the matched_rule preload, which pluck would turn into a JOIN on rules.
        rows = ApplicantsQuery.call(status:, q:, after: cursor).unscope(:includes).limit(limit + 1).pluck(:id, :created_at)
        more = rows.size > limit
        rows = rows.first(limit)
        [ rows.map(&:first), (ApplicantsQuery::Cursor.encode(rows.last.last, rows.last.first) if more) ]
      end

      rules = rule_summaries(tokens.fetch(:rules))
      Page.new(applicants: records(ids).map { |attributes| with_rule(attributes, rules) }, next_cursor:)
    end

    def expire(ids)
      keys = Array(ids).map { |id| record_key(id) }
      store.delete_multi(keys) if keys.any?
    end

    def expire_pages! = store.write(TOKEN_KEYS[:pages], new_token)

    def expire_rules! = store.write(TOKEN_KEYS[:rules], new_token)

    private
      # The applicants for these ids, in order. Ids deleted since the page was cached are skipped.
      def records(ids)
        keys = ids.index_with { |id| record_key(id) }
        cached = store.read_multi(*keys.values)
        missing = ids.reject { |id| cached.key?(keys[id]) }

        if missing.any?
          loaded = Applicant.where(id: missing).to_h { |applicant| [ keys[applicant.id], applicant.as_json ] }
          store.write_multi(loaded, expires_in: jittered(RECORD_TTL)) if loaded.any?
          cached.merge!(loaded)
        end

        ids.filter_map { |id| cached[keys[id]] }
      end

      def rule_summaries(token)
        store.fetch("rules/v#{VERSION}/summaries/#{token}") do
          Rule.pluck(:id, :name, :outcome).to_h { |id, name, outcome| [ id, { "id" => id, "name" => name, "outcome" => outcome } ] }
        end
      end

      # A rule deleted since the applicant was cached reads as no rule, as it does in the database.
      def with_rule(attributes, rules)
        attributes.merge("matched_rule" => rules[attributes["matched_rule_id"]])
      end

      # Both tokens in one round trip. A missing token (never set, or evicted) gets a fresh one.
      def tokens
        found = store.read_multi(*TOKEN_KEYS.values)
        TOKEN_KEYS.transform_values { |key| found[key] || new_token.tap { |token| store.write(key, token) } }
      end

      def record_key(id) = "applicants/v#{VERSION}/#{id}"

      # Filters are hashed so a long search term can't make a long key.
      def page_key(token, **filters)
        "applicants/v#{VERSION}/page/#{token}/#{Digest::SHA256.hexdigest(filters.to_json)}"
      end

      def new_token = SecureRandom.alphanumeric(12)

      def jittered(ttl) = ttl + rand * TTL_JITTER * ttl
  end
end
