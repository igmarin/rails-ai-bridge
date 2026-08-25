# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::ContextProviderClient do
  let(:policy) { instance_double(RailsAiBridge::Registry::EndpointPolicy) }
  let(:transport_factory) { instance_double(Proc) }
  let(:provider) do
    RailsAiBridge::Registry::ContextProviderDefinition.new(
      type: 'mcp',
      endpoint: 'https://example.com/mcp',
      optional: false,
      tools: [
        RailsAiBridge::Registry::ContextToolSpec.new(name: 'get_status', field: nil, arguments: nil)
      ]
    )
  end

  subject(:client) do
    described_class.new(
      provider: provider,
      policy: policy,
      transport_factory: transport_factory,
      auth_resolver: nil
    )
  end

  describe '#call_tool' do
    before do
      allow(transport_factory).to receive(:call)
    end

    it 'returns an error result when the endpoint policy rejects the URL' do
      allow(policy).to receive(:call).with('https://example.com/mcp').and_return(
        RailsAiBridge::Registry::EndpointPolicy::Result.new(
          success: false,
          error: RailsAiBridge::Registry::PolicyError.new('host is not in the allowlist'),
          uri: nil,
          addresses: nil
        )
      )

      result = client.call_tool('get_status', arguments: {})

      expect(result.status).to eq(:error)
      expect(result.error).to be_a(RailsAiBridge::Registry::PolicyError)
      expect(transport_factory).not_to have_received(:call)
    end
  end
end
