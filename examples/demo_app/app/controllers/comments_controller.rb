# frozen_string_literal: true

class CommentsController < ApplicationController
  def create
    @post = Post.find(params[:post_id] || params.expect(:comment)[:post_id])
    @comment = @post.comments.create!(comment_params)
    redirect_to @post
  end

  def destroy
    @comment = Comment.find(params.expect(:id))
    @comment.destroy
    redirect_to @comment.post
  end

  private

  def comment_params
    params.expect(comment: [:body])
  end
end
