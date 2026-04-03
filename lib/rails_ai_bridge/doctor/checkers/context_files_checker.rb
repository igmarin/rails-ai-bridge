# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      class ContextFilesChecker < BaseChecker
        def call
          claude_path = File.join(app.root, "CLAUDE.md")
          check(
            "Bridge files",
            File.exist?(claude_path),
            pass: { message: "CLAUDE.md exists" },
            fail: { status: :warn, message: "No bridge files generated yet", fix: "Run `rails ai:bridge` to generate them" }
          )
        end
      end
    end
  end
end
