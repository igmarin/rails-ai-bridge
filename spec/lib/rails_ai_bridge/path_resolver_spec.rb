# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::PathResolver do
  let(:fixture) do
    root_path = Dir.mktmpdir('rails-ai-bridge-path-resolver')
    root = Pathname.new(root_path)
    models_dir = root.join('domain/models')

    { root_path:, root:, models_dir: }
  end

  let(:app) do
    double(
      'Rails::Application',
      root: fixture[:root],
      paths: { 'app/models' => [models_dir.to_s] }
    )
  end
  let(:models_dir) { fixture[:models_dir] }
  let(:resolver) { described_class.new(app) }

  after { FileUtils.rm_rf(fixture[:root_path]) }

  before do
    FileUtils.mkdir_p(models_dir.join('billing'))
    File.write(models_dir.join('billing/account.rb'), 'class Billing::Account; end')
  end

  it 'resolves configured Rails path directories before conventional fallbacks' do
    expect(resolver.directories_for('app/models')).to eq([models_dir.to_s])
  end

  it 'finds files below configured Rails paths' do
    expect(resolver.existing_file_for('app/models', 'billing/account.rb')).to eq(
      models_dir.join('billing/account.rb').to_s
    )
  end

  it 'rejects traversal in glob patterns before reading the filesystem' do
    expect { resolver.glob_for('app/models', '../**/*.rb') }.to raise_error(
      ArgumentError,
      'pattern must be a safe relative path'
    )
  end

  it 'rejects absolute glob patterns before reading the filesystem' do
    expect { resolver.glob_for('app/models', '/tmp/**/*.rb') }.to raise_error(
      ArgumentError,
      'pattern must be a safe relative path'
    )
  end

  it 'rejects traversal in relative file lookups' do
    expect { resolver.existing_file_for('app/models', '../secrets.yml') }.to raise_error(
      ArgumentError,
      'relative_file must be a safe relative path'
    )
  end

  it 'maps configured filesystem paths back to stable logical context paths' do
    expect(resolver.logical_file_path(models_dir.join('billing/account.rb'), logical_path: 'app/models')).to eq(
      'app/models/billing/account.rb'
    )
  end

  it 'falls back to conventional root-relative paths when no configured path exists' do
    expect(resolver.directories_for('app/controllers')).to eq([fixture[:root].join('app/controllers').to_s])
  end

  context 'when configured Rails paths raise unexpectedly' do
    let(:app) do
      double(
        'Rails::Application',
        root: fixture[:root],
        paths: path_registry
      )
    end
    let(:path_registry) do
      double('Rails paths').tap do |registry|
        allow(registry).to receive(:[]).with('app/models').and_raise(StandardError, 'boom')
      end
    end

    it 'logs and falls back to the conventional directory outside development' do
      allow(Rails.logger).to receive(:error)

      expect(resolver.directories_for('app/models')).to eq([fixture[:root].join('app/models').to_s])
      expect(Rails.logger).to have_received(:error).with(%r{failed to read path "app/models"})
    end
  end
end
