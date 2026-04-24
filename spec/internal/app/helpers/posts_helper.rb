# frozen_string_literal: true

# Helper methods for post views
module PostsHelper
  def post_excerpt(post, length: 100)
    truncate(post.body, length: length)
  end
end
