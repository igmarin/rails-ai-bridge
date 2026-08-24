# frozen_string_literal: true

# Fixture Archspec.rb for the archspec rule spec. Mirrors the gem's real
# component model and rules so each rule can be proven to catch a violation.
# Fixture files use distinct top-level module names per component to avoid the
# namespace-reopening false positives present in the real gem.

source '**/*.rb'

component :config, in: 'config/**/*.rb'
component :introspectors, in: 'introspectors/**/*.rb'
component :runtime_context, in: 'runtime_context/**/*.rb'
component :tools, in: 'tools/**/*.rb'
component :serializers, in: 'serializers/**/*.rb'
component :registry, in: 'registry/**/*.rb'
component :mcp_transport, in: 'mcp_transport/**/*.rb'
component :rubydex, in: 'rubydex/**/*.rb'

config.cannot_use :tools, :serializers, :mcp_transport, :introspectors
registry.cannot_use :tools, :serializers, :mcp_transport
rubydex.cannot_use :tools, :serializers, :mcp_transport
introspectors.cannot_use :tools, :serializers, :mcp_transport
serializers.cannot_use :introspectors, :mcp_transport

no_cycles among: %i[config introspectors runtime_context tools serializers
                    registry mcp_transport rubydex]
