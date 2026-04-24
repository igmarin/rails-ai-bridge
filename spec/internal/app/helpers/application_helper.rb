# frozen_string_literal: true

# Helper methods for the test application views
module ApplicationHelper
  def page_title(title)
    content_tag(:h1, title)
  end
end
