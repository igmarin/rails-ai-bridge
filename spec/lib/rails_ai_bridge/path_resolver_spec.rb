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

  it 'maps configured filesystem paths back to stable logical context paths' do
    expect(resolver.logical_file_path(models_dir.join('billing/account.rb'), logical_path: 'app/models')).to eq(
      'app/models/billing/account.rb'
    )
  end

  it 'falls back to conventional root-relative paths when no configured path exists' do
    expect(resolver.directories_for('app/controllers')).to eq([fixture[:root].join('app/controllers').to_s])
  end
end
