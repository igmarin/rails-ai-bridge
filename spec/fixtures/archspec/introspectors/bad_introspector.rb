# frozen_string_literal: true

# Violates introspectors.cannot_use :serializers — introspector reaches into serializers.
module FixtureIntrospectors
  class BadIntrospector
    def uses_serializer
      FixtureSerializers::SerializerTarget
    end
  end
end
