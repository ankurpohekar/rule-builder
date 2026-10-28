redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

Sidekiq.configure_client do |config|
  config.redis = redis
end

Sidekiq.configure_server do |config|
  config.redis = redis

  # Rule re-evaluation must never run two at a time, or an older run could overwrite
  # statuses computed from newer rules. A single-threaded capsule processes the
  # "evaluation" queue strictly in order; other queues keep their normal concurrency.
  # Keep "evaluation" out of config/sidekiq.yml so no other thread picks it up.
  config.capsule("serial") do |capsule|
    capsule.concurrency = 1
    capsule.queues = %w[evaluation]
  end
end

# --- Web UI (mounted at /sidekiq in config/routes.rb) ---
require "sidekiq/web"

# The app is API-only, so it has no cookies or session. Give them to the dashboard alone
# instead of turning them on for every API request.
Sidekiq::Web.use ActionDispatch::Cookies
Sidekiq::Web.use ActionDispatch::Session::CookieStore,
  key: "_rule_builder_sidekiq", same_site: :strict, secure: Rails.env.production?

# Basic auth whenever credentials are set. Routes refuse to mount the UI in production without them.
if ENV["SIDEKIQ_WEB_USERNAME"].present? && ENV["SIDEKIQ_WEB_PASSWORD"].present?
  # Compare digests so neither the length nor the content leaks through timing.
  matches = ->(given, expected) do
    ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(given), Digest::SHA256.hexdigest(expected))
  end

  Sidekiq::Web.use Rack::Auth::Basic, "Sidekiq" do |username, password|
    # `&` (not `&&`) so both checks always run.
    matches.(username, ENV["SIDEKIQ_WEB_USERNAME"]) & matches.(password, ENV["SIDEKIQ_WEB_PASSWORD"])
  end
end
