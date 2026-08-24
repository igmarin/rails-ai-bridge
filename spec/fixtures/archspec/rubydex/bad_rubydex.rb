# frozen_string_literal: true

# Violates rubydex.cannot_use :serializers — rubydex reaches into serializers.
module FixtureRubydex
  def self.uses_serializer
    FixtureSerializers::SerializerTarget
  end
end
