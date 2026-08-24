# frozen_string_literal: true

# Proves each ArchSpec rule in the fixture Archspec.rb catches a deliberate
# violation. The fixtures live under spec/fixtures/archspec/ with their own
# Archspec.rb so the real gem config is not affected.
#
# Each fixture file uses distinct top-level module names per component to avoid
# the namespace-reopening false positives that the real gem's single
# RailsAiBridge module produces.

require 'json'

RSpec.describe 'ArchSpec component rules', :archspec do
  let(:fixture_config) { 'spec/fixtures/archspec/Archspec.rb' }
  let(:violations) do
    output = `bundle exec archspec check --config #{fixture_config} --format json 2>/dev/null`
    data = JSON.parse(output)
    data['violations'] || data['diagnostics'] || []
  end

  def violation?(rule:, message_part:, path_part:)
    violations.any? do |v|
      v['rule'] == rule &&
        v['message'].include?(message_part) &&
        v['path'].include?(path_part)
    end
  end

  it 'runs the fixture check and reports violations' do
    expect(violations).not_to be_empty
  end

  it 'catches config depending on tools' do
    expect(violation?(rule: 'dependencies.forbid',
                      message_part: 'config must not depend on tools',
                      path_part: 'config/bad_config.rb')).to be true
  end

  it 'catches introspectors depending on serializers' do
    expect(violation?(rule: 'dependencies.forbid',
                      message_part: 'introspectors must not depend on serializers',
                      path_part: 'introspectors/bad_introspector.rb')).to be true
  end

  it 'catches registry depending on tools' do
    expect(violation?(rule: 'dependencies.forbid',
                      message_part: 'registry must not depend on tools',
                      path_part: 'registry/bad_registry.rb')).to be true
  end

  it 'catches rubydex depending on serializers' do
    expect(violation?(rule: 'dependencies.forbid',
                      message_part: 'rubydex must not depend on serializers',
                      path_part: 'rubydex/bad_rubydex.rb')).to be true
  end

  it 'catches serializers depending on introspectors' do
    expect(violation?(rule: 'dependencies.forbid',
                      message_part: 'serializers must not depend on introspectors',
                      path_part: 'serializers/bad_serializer.rb')).to be true
  end

  it 'catches cross-component cycles' do
    expect(violation?(rule: 'dependencies.no_cycles',
                      message_part: 'cycle',
                      path_part: 'mcp_transport/cycle_transport.rb')).to be true
  end

  it 'passes the real gem Archspec.rb with zero violations' do
    output = `bundle exec archspec check --format json 2>/dev/null`
    data = JSON.parse(output)
    real_violations = data['violations'] || data['diagnostics'] || []
    expect(real_violations).to be_empty
  end
end
