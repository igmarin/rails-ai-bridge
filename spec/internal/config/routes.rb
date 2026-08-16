# frozen_string_literal: true

Rails.application.routes.draw do
  resources :users
  resources :posts

  # Named with `as:` so the helper is profile_path, not a path-derived me_path.
  get '/me', to: 'users#show', as: :profile

  # Unnamed on purpose (`as: nil`) — Rails defines no helper.
  get '/legacy-ping', to: 'users#index', as: nil
end
