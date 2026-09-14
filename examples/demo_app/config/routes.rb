# frozen_string_literal: true

Rails.application.routes.draw do
  root 'posts#index'
  resources :posts
  resources :comments, only: %i[create destroy]
end
