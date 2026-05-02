Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :articles, only: %i[index show create update]
      resources :tokens, only: %i[create destroy]
    end
  end
end
