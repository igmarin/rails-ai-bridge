Rails.application.routes.draw do
  resources :accounts, only: %i[index show create update]
  resources :customers, only: %i[index show create update]
  resources :opportunities, only: %i[index show create update]
  resources :invoices, only: %i[index show]
  resources :subscriptions, only: %i[index show]
  resources :reports, only: %i[index show]
end
