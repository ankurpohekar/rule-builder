Rails.application.routes.draw do
  namespace :api do
    resources :applicants do
      post :evaluate, on: :collection
    end
    resources :rules do
      post :draft, on: :collection
    end
    resource :schema, only: :show, controller: :schema
  end

  # Sidekiq dashboard. Open in development; in production only when basic auth credentials are set.
  if Rails.env.local? || (ENV["SIDEKIQ_WEB_USERNAME"].present? && ENV["SIDEKIQ_WEB_PASSWORD"].present?)
    mount Sidekiq::Web => "/sidekiq"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
