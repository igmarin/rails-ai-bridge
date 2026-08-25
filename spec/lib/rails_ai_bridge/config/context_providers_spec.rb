# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Config::ContextProviders do
  describe '#initialize' do
    it 'sets safe defaults' do
      config = described_class.new

      expect(config.enabled).to be(false)
      expect(config.allowed_hosts).to eq([])
      expect(config.allowed_loopback_ports).to eq([3000, 9292])
      expect(config.timeout_seconds).to eq(10)
      expect(config.aggregation_budget_seconds).to eq(30)
      expect(config.max_response_bytes).to eq(1_048_576)
      expect(config.max_providers).to eq(8)
      expect(config.max_tools_per_provider).to eq(16)
      expect(config.allow_private_networks).to be(false)
      expect(config.auth_resolver).to be_nil
    end
  end

  describe '#timeout_seconds=' do
    it 'accepts a valid positive float' do
      config = described_class.new
      config.timeout_seconds = 5.5

      expect(config.timeout_seconds).to eq(5.5)
    end

    it 'rejects non-numeric values' do
      config = described_class.new

      expect { config.timeout_seconds = 'fast' }.to raise_error(RailsAiBridge::ConfigurationError, /timeout_seconds must be a finite positive number/)
    end

    it 'rejects zero' do
      config = described_class.new

      expect { config.timeout_seconds = 0 }.to raise_error(RailsAiBridge::ConfigurationError, /timeout_seconds must be >= 0.1/)
    end

    it 'rejects negative values' do
      config = described_class.new

      expect { config.timeout_seconds = -1 }.to raise_error(RailsAiBridge::ConfigurationError, /timeout_seconds must be >= 0.1/)
    end

    it 'rejects non-finite values' do
      config = described_class.new

      expect { config.timeout_seconds = Float::INFINITY }.to raise_error(RailsAiBridge::ConfigurationError, /timeout_seconds must be a finite positive number/)
    end
  end

  describe '#max_providers=' do
    it 'accepts a valid positive integer' do
      config = described_class.new
      config.max_providers = 4

      expect(config.max_providers).to eq(4)
    end

    it 'rejects non-integer values' do
      config = described_class.new

      expect { config.max_providers = 'many' }.to raise_error(RailsAiBridge::ConfigurationError, /max_providers must be an integer >= 1/)
    end

    it 'rejects zero' do
      config = described_class.new

      expect { config.max_providers = 0 }.to raise_error(RailsAiBridge::ConfigurationError, /max_providers must be an integer >= 1/)
    end

    it 'rejects negative values' do
      config = described_class.new

      expect { config.max_providers = -1 }.to raise_error(RailsAiBridge::ConfigurationError, /max_providers must be an integer >= 1/)
    end
  end

  describe '#max_response_bytes=' do
    it 'accepts a valid positive integer' do
      config = described_class.new
      config.max_response_bytes = 2_097_152

      expect(config.max_response_bytes).to eq(2_097_152)
    end

    it 'rejects zero' do
      config = described_class.new

      expect { config.max_response_bytes = 0 }.to raise_error(RailsAiBridge::ConfigurationError, /max_response_bytes must be an integer >= 1/)
    end
  end

  describe '#aggregation_budget_seconds=' do
    it 'accepts a valid positive float' do
      config = described_class.new
      config.aggregation_budget_seconds = 60.0

      expect(config.aggregation_budget_seconds).to eq(60.0)
    end

    it 'rejects negative values' do
      config = described_class.new

      expect { config.aggregation_budget_seconds = -1 }.to raise_error(RailsAiBridge::ConfigurationError, /aggregation_budget_seconds must be >= 0.1/)
    end
  end

  describe '#max_tools_per_provider=' do
    it 'accepts a valid positive integer' do
      config = described_class.new
      config.max_tools_per_provider = 4

      expect(config.max_tools_per_provider).to eq(4)
    end
  end
end

RSpec.describe RailsAiBridge::Configuration do
  describe '#context_providers' do
    it 'exposes a Config::ContextProviders instance' do
      config = described_class.new

      expect(config.context_providers).to be_a(RailsAiBridge::Config::ContextProviders)
      expect(config.context_providers.enabled).to be(false)
    end
  end
end
