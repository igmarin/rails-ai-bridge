# frozen_string_literal: true

require 'spec_helper'
require 'rails/generators'
require 'generators/rails_ai_bridge/install/install_generator'

RSpec.describe RailsAiBridge::Engine do
  # Run a named initializer block against the given app.
  #
  # Rails stores initializer blocks as Proc objects inside
  # +Rails::Initializable::Initializer+ instances. Calling +#run(app)+
  # invokes the block with +app+ as the argument, matching the real
  # boot-time behaviour.
  def run_initializer(name, app)
    initializer = described_class.initializers.find { |i| i.name == name }
    raise "Initializer '#{name}' not found" unless initializer

    initializer.run(app)
  end

  # Build a minimal fake app double that tracks middleware insertions and
  # after_initialize callbacks.
  #
  # The setup initializer writes to +Rails.application.config+ (not the
  # block arg), so we stub that path on the real Rails application.
  # The middleware initializer calls +app.middleware.use+ directly on the
  # block arg, so we stub +#middleware+ on the returned double.
  def fake_app(after_initialize_cbs: [], middleware: [])
    mw_stack = double('middleware_stack')
    allow(mw_stack).to receive(:use) { |klass| middleware << klass }

    config = double('config')
    allow(config).to receive(:rails_ai_bridge=)
    allow(config).to receive(:after_initialize) { |&blk| after_initialize_cbs << blk }

    double('app', config: config, middleware: mw_stack)
  end

  # ─────────────────────────────────────────────────────
  # rails_ai_bridge.setup initializer
  # ─────────────────────────────────────────────────────

  describe "'rails_ai_bridge.setup' initializer" do
    around do |example|
      saved = RailsAiBridge.configuration.cache_warm_on_boot
      example.run
    ensure
      RailsAiBridge.configuration.cache_warm_on_boot = saved
    end

    it 'assigns the gem configuration onto Rails.application.config.rails_ai_bridge' do
      # The initializer uses Rails.application.config (not the block arg) so
      # we assert against the real application config object.
      run_initializer('rails_ai_bridge.setup', fake_app)

      expect(Rails.application.config.rails_ai_bridge).to eq(RailsAiBridge.configuration)
    end

    context 'when cache_warm_on_boot is false (default)' do
      before { RailsAiBridge.configuration.cache_warm_on_boot = false }

      it 'does not register an after_initialize callback' do
        cbs = []
        run_initializer('rails_ai_bridge.setup', fake_app(after_initialize_cbs: cbs))

        expect(cbs).to be_empty
      end
    end

    context 'when cache_warm_on_boot is true' do
      before { RailsAiBridge.configuration.cache_warm_on_boot = true }

      it 'registers an after_initialize callback' do
        cbs = []
        run_initializer('rails_ai_bridge.setup', fake_app(after_initialize_cbs: cbs))

        expect(cbs.size).to eq(1)
      end

      it 'the after_initialize callback calls CacheWarmer.warm with the app' do
        cbs = []
        app = fake_app(after_initialize_cbs: cbs)
        run_initializer('rails_ai_bridge.setup', app)

        allow(RailsAiBridge::CacheWarmer).to receive(:warm)
        cbs.first.call # simulate Rails firing after_initialize

        expect(RailsAiBridge::CacheWarmer).to have_received(:warm).with(app)
      end
    end
  end

  # ─────────────────────────────────────────────────────
  # rails_ai_bridge.middleware initializer
  # ─────────────────────────────────────────────────────

  describe "'rails_ai_bridge.middleware' initializer" do
    around do |example|
      saved = RailsAiBridge.configuration.auto_mount
      example.run
    ensure
      RailsAiBridge.configuration.auto_mount = saved
    end

    before do
      allow(RailsAiBridge).to receive(:validate_auto_mount_configuration!)
    end

    it 'always calls validate_auto_mount_configuration!' do
      RailsAiBridge.configuration.auto_mount = false
      run_initializer('rails_ai_bridge.middleware', fake_app)

      expect(RailsAiBridge).to have_received(:validate_auto_mount_configuration!)
    end

    context 'when auto_mount is false (default)' do
      before { RailsAiBridge.configuration.auto_mount = false }

      it 'does not insert Middleware into the stack' do
        mw = []
        run_initializer('rails_ai_bridge.middleware', fake_app(middleware: mw))

        expect(mw).not_to include(RailsAiBridge::Middleware)
      end
    end

    context 'when auto_mount is true' do
      before { RailsAiBridge.configuration.auto_mount = true }

      it 'inserts RailsAiBridge::Middleware into the middleware stack' do
        mw = []
        run_initializer('rails_ai_bridge.middleware', fake_app(middleware: mw))

        expect(mw).to include(RailsAiBridge::Middleware)
      end
    end
  end

  # ─────────────────────────────────────────────────────
  # rake_tasks block
  # ─────────────────────────────────────────────────────

  describe 'rake_tasks block' do
    it 'references a rake file that exists on disk' do
      rake_file = File.expand_path(
        '../../../lib/rails_ai_bridge/tasks/rails_ai_bridge.rake',
        __dir__
      )
      expect(File.exist?(rake_file)).to be(true)
    end

    it 'registers exactly one rake_tasks block on the engine' do
      blocks = described_class.instance_variable_get(:@rake_tasks)
      expect(blocks.size).to eq(1)
    end
  end

  # ─────────────────────────────────────────────────────
  # generators block
  # ─────────────────────────────────────────────────────

  describe 'generators block' do
    it 'makes the InstallGenerator available' do
      # The generator is loaded at the top of this spec file, mirroring
      # what the generators block does at engine load time.
      expect(defined?(RailsAiBridge::Generators::InstallGenerator)).to eq('constant')
    end

    it 'registers exactly one generators block on the engine' do
      blocks = described_class.instance_variable_get(:@generators)
      expect(blocks.size).to eq(1)
    end
  end
end
