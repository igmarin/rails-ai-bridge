# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      class GemsChecker < BaseChecker
        def call
          lock_path = File.join(app.root, "Gemfile.lock")
          check(
            "Gems",
            File.exist?(lock_path),
            pass: { message: "Gemfile.lock found" },
            fail: { status: :warn, message: "Gemfile.lock not found", fix: "Run `bundle install` to generate it" }
          )
        end
      end
    end
  end
end
