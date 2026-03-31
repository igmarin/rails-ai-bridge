# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Action Mailbox section with mailbox class names.
      class ActionMailboxFormatter < Base
        # @return [String, nil]
        def call
          data = context[:action_mailbox]
          return unless data
          return if data[:error]
          return unless data[:mailboxes]&.any?

          lines = [ "## Action Mailbox" ]
          data[:mailboxes].each { |m| lines << "- `#{m[:name]}`" }
          lines.join("\n")
        end
      end
    end
  end
end
