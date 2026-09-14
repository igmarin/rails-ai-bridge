# frozen_string_literal: true

class PostsController < ApplicationController
  def index
    @posts = Post.published.recent
  end

  def show
    @post = Post.find(params.expect(:id))
  end

  def create
    @post = Post.create!(post_params)
    redirect_to @post
  end

  private

  def post_params
    params.expect(post: %i[title body published])
  end
end
