# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters::Sections
      # Renders the Action Mailbox section with mailbox class names.
      #
      # @see Formatters::Providers::SectionFormatter
      class ActionMailboxFormatter < SectionFormatter
        section :action_mailbox

        private

        def render(data)
          return unless data[:mailboxes]&.any?

          lines = ['## Action Mailbox']
          data[:mailboxes].each { |m| lines << "- `#{m[:name]}`" }
          lines.join("\n")
        end
      end
    end
  end
end
