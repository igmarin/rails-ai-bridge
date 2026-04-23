Rails.application.routes.draw do
  mount Sidekiq::Web => "/sidekiq"
  mount Flipper::UI, at: "/flipper"
  mount PgHero::Engine, at: "/pghero"

  resources :posts
end
