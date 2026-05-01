Rails.application.routes.draw do
  root "conversations#index"
  resources :conversations, only: %i[index show create]
  resources :messages, only: %i[create update destroy]
end
