# frozen_string_literal: true

# Controller for managing posts in the test application
# :reek:InstanceVariableAssumption
class PostsController < ApplicationController
  before_action :set_post, only: %i[show edit update destroy]

  def index
    @posts = Post.all
  end

  def show
  end

  def new
    @post = Post.new
  end

  def create
    @post = Post.new(post_params)
    respond_to_formats(@post.save)
  end

  def edit
  end

  def update
    @post.update(post_params)
    redirect_to @post
  end

  def destroy
    @post.destroy
    redirect_to posts_path
  end

  private

  def respond_to_formats(saved)
    respond_to do |format|
      handle_save_response(format, saved)
    end
  end

  # :reek:ControlParameter :reek:DuplicateMethodCall :reek:InstanceVariableAssumption :reek:TooManyStatements
  def handle_save_response(format, saved)
    if saved
      format.html { redirect_to @post }
      format.json { render json: @post, status: :created }
    else
      format.html { render :new }
      format.json { render json: @post.errors, status: :unprocessable_entity }
    end
  end

  def set_post
    @post = Post.find(params[:id])
  end

  def post_params
    params.require(:post).permit(:title, :body, :user_id)
  end
end
