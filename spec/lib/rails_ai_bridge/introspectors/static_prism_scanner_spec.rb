# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe RailsAiBridge::Introspectors::StaticPrismScanner do
  describe 'when Prism cannot be loaded' do
    subject(:scanner) do
      described_class.new(max_files: 10, loader: -> { raise LoadError, 'cannot load such file -- prism' })
    end

    it 'returns an error hash instead of raising' do
      result = scanner.facts_for(__FILE__)

      expect(result).to have_key(:error)
      expect(result[:error]).to include('prism')
    end
  end

  describe 'when Prism is available' do
    subject(:scanner) { described_class.new(max_files: 10) }

    let(:dir) { Dir.mktmpdir('static_prism_scanner') }
    let(:controller_path) { File.join(dir, 'users_controller.rb') }

    before do
      begin
        require 'prism'
      rescue LoadError
        skip 'prism is not available on this Ruby'
      end

      File.write(controller_path, <<~RUBY)
        class UsersController < ApplicationController
          before_action :authenticate_user!, :set_user
          after_action :log_request
          helper_method :current_user
          def index; end

          def show
            before_action :not_a_filter
          end
        end
      RUBY
    end

    after { FileUtils.rm_rf(dir) }

    it 'emits prism-provenance facts for controller filter macros' do
      facts = scanner.facts_for(controller_path)[:facts]

      expect(facts).to include(
        hash_including(kind: :before_action, name: 'authenticate_user!', provenance: :prism, line: 2),
        hash_including(kind: :before_action, name: 'set_user', provenance: :prism, line: 2),
        hash_including(kind: :after_action, name: 'log_request', provenance: :prism, line: 3)
      )
    end

    it 'ignores calls that are not filter macros' do
      names = scanner.facts_for(controller_path)[:facts].pluck(:name)

      expect(names).not_to include('current_user')
    end

    it 'ignores filter macros inside method bodies' do
      names = scanner.facts_for(controller_path)[:facts].pluck(:name)

      expect(names).not_to include('not_a_filter')
    end

    it 'keeps filter macros registered in included blocks' do
      concern_path = File.join(dir, 'auditable.rb')
      File.write(concern_path, <<~RUBY)
        module Auditable
          extend ActiveSupport::Concern

          included do
            before_action :audit_request
          end
        end
      RUBY

      names = scanner.facts_for(concern_path)[:facts].pluck(:name)

      expect(names).to include('audit_request')
    end

    it 'stops reading files once max_files have been scanned' do
      capped = described_class.new(max_files: 1)
      capped.facts_for(controller_path)

      expect(capped.facts_for(controller_path)[:error]).to include('prism_max_files')
    end

    it 'reports instance method definitions as prism-provenance facts' do
      facts = scanner.facts_for(controller_path)[:facts]

      expect(facts).to include(
        hash_including(kind: :def, name: 'index', provenance: :prism, line: 5),
        hash_including(kind: :def, name: 'show', provenance: :prism, line: 7)
      )
    end

    it 'skips singleton methods and methods defined inside method bodies' do
      nested_path = File.join(dir, 'nested_defs_controller.rb')
      File.write(nested_path, <<~RUBY)
        class NestedDefsController < ApplicationController
          def self.helper_params; end

          def index
            def inner_params; end
          end
        end
      RUBY

      names = scanner.facts_for(nested_path)[:facts].pluck(:name)

      expect(names).to include('index')
      expect(names).not_to include('helper_params')
      expect(names).not_to include('inner_params')
    end

    it 'returns an error hash for a missing file instead of raising' do
      expect(scanner.facts_for(File.join(dir, 'missing.rb'))).to have_key(:error)
    end
  end
end
