# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      class BaseChecker
        attr_reader :app

        def initialize(app)
          @app = app
        end

        def call
          raise NotImplementedError, "subclasses must implement #call"
        end

        private

        def check(name, condition, pass:, fail:)
          options = condition ? pass : fail
          default_pass_options = { status: :pass, fix: nil }
          final_options = { name: name }.merge(default_pass_options).merge(options)

          new_check(**final_options)
        end

        def new_check(name:, status:, message:, fix:)
          RailsAiBridge::Doctor::Check.new(name: name, status: status, message: message, fix: fix)
        end
      end
    end
  end
end
