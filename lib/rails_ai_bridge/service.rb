# frozen_string_literal: true

module RailsAiBridge
  class Service
    class << self
      def call(*args, **kwargs)
        new(*args, **kwargs).call
      end
    end

    def initialize(*args, **kwargs)
      # Standard initialization
      @args = args
      @kwargs = kwargs
    end

    def call
      raise NotImplementedError, "#{self.class} must implement #call"
    end
  end
end
