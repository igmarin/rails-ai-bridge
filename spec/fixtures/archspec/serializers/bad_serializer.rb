# frozen_string_literal: true

# Violates serializers.cannot_use :introspectors — serializer reaches into introspectors.
module FixtureSerializers
  class BadSerializer
    def uses_introspector
      FixtureIntrospectors::IntrospectorTarget
    end
  end
end
