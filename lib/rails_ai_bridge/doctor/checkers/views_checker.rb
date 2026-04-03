# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      class ViewsChecker < BaseChecker
        def call
          views_path = File.join(app.root, "app/views", "**/*")
          views = Dir.glob(views_path).reject { |f| File.directory?(f) }

          check(
            "Views",
            views.any?,
            pass: { message: "#{views.size} view files found" },
            fail: { status: :warn, message: "No view files found in app/views/", fix: "Views are generated alongside controllers" }
          )
        end
      end
    end
  end
end
