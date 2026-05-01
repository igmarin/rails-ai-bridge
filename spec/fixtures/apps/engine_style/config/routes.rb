Rails.application.routes.draw do
  mount Billing::Engine => "/billing"

  namespace :billing do
    resources :customers, only: %i[index show]
    resources :subscriptions, only: %i[index show create update]
    resources :invoices, only: %i[index show]
  end
end
