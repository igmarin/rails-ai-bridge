Rails.application.routes.draw do
  resources :health_checks, only: %i[index]
  get "up", to: "health_checks#show"
end
