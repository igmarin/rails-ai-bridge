# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::RubydexAdapter::Serializer do
  let(:root) { '/tmp/test_root' }
  let(:serializer) { described_class.new(root) }

  describe '#declaration_to_hash' do
    it 'extracts name, unqualified_name, and type from a declaration' do
      decl = double(
        'decl',
        name: 'MyModule::MyClass',
        class: double(name: 'Rubydex::ClassDeclaration'),
        respond_to?: false
      )
      allow(decl).to receive(:respond_to?).with(:unqualified_name).and_return(true)
      allow(decl).to receive(:unqualified_name).and_return('MyClass')

      result = serializer.declaration_to_hash(decl)

      expect(result).to include(name: 'MyModule::MyClass', unqualified_name: 'MyClass', type: 'class')
      expect(result).not_to have_key(:definitions)
      expect(result).not_to have_key(:ancestors)
      expect(result).not_to have_key(:descendants)
      expect(result).not_to have_key(:owner)
    end

    it 'omits unqualified_name when not supported' do
      decl = double(
        'decl',
        name: 'Foo',
        class: double(name: 'Rubydex::ClassDeclaration'),
        respond_to?: false
      )
      allow(decl).to receive(:respond_to?).with(:unqualified_name).and_return(false)

      result = serializer.declaration_to_hash(decl)

      expect(result).not_to have_key(:unqualified_name)
    end
  end

  describe '#detailed_declaration_to_hash' do
    let(:defn) do
      double(
        'defn',
        name: 'my_method(',
        respond_to?: false
      )
    end
    let(:ancestor) { double('ancestor', name: 'ActiveRecord::Base') }
    let(:descendant) { double('descendant', name: 'AdminUser') }
    let(:decl) do
      double(
        'decl',
        name: 'User',
        class: double(name: 'Rubydex::ClassDeclaration'),
        definitions: [defn],
        ancestors: [ancestor],
        descendants: [descendant],
        owner: double(name: 'MyApp'),
        respond_to?: false
      )
    end

    before do
      allow(defn).to receive(:respond_to?).with(:location).and_return(false)
      allow(defn).to receive(:respond_to?).with(:comments).and_return(false)
      allow(defn).to receive(:respond_to?).with(:deprecated?).and_return(false)
      allow(decl).to receive(:respond_to?).with(:unqualified_name).and_return(true)
      allow(decl).to receive(:unqualified_name).and_return('User')
      allow(decl).to receive(:respond_to?).with(:definitions).and_return(true)
      allow(decl).to receive(:respond_to?).with(:ancestors).and_return(true)
      allow(decl).to receive(:respond_to?).with(:descendants).and_return(true)
      allow(decl).to receive(:respond_to?).with(:member).and_return(true)
      allow(decl).to receive(:respond_to?).with(:owner).and_return(true)
    end

    it 'includes definitions, ancestors, descendants, and owner' do
      result = serializer.detailed_declaration_to_hash(decl)

      expect(result).to include(name: 'User', unqualified_name: 'User', type: 'class')
      expect(result[:definitions]).to be_an(Array)
      expect(result[:definitions].first).to include(name: 'my_method(')
      expect(result[:ancestors]).to eq(['ActiveRecord::Base'])
      expect(result[:descendants]).to eq(['AdminUser'])
      expect(result[:owner]).to eq('MyApp')
    end
  end

  describe '#definition_to_hash' do
    let(:location) { double('location', to_s: '/tmp/test_root/app/models/user.rb:10') }
    let(:defn) do
      double(
        'defn',
        name: 'save_with_validation',
        respond_to?: false
      )
    end

    before do
      allow(defn).to receive(:respond_to?).with(:location).and_return(true)
      allow(defn).to receive(:location).and_return(location)
      allow(location).to receive(:respond_to?).with(:path).and_return(true)
      allow(location).to receive(:path).and_return('/tmp/test_root/app/models/user.rb')
      allow(defn).to receive(:respond_to?).with(:comments).and_return(false)
      allow(defn).to receive(:respond_to?).with(:deprecated?).and_return(false)
    end

    it 'extracts name and location' do
      result = serializer.definition_to_hash(defn)

      expect(result).to include(name: 'save_with_validation')
      expect(result[:location]).to eq('app/models/user.rb')
    end

    it 'includes comments when present' do
      allow(defn).to receive(:respond_to?).with(:comments).and_return(true)
      allow(defn).to receive(:comments).and_return('Saves the record with validations')

      result = serializer.definition_to_hash(defn)

      expect(result[:comments]).to eq('Saves the record with validations')
    end

    it 'flags deprecated definitions' do
      allow(defn).to receive(:respond_to?).with(:deprecated?).and_return(true)
      allow(defn).to receive(:deprecated?).and_return(true)

      result = serializer.definition_to_hash(defn)

      expect(result[:deprecated]).to be(true)
    end
  end

  describe '#format_location' do
    it 'returns nil when location is nil' do
      result = serializer.format_location(nil)

      expect(result).to be_nil
    end

    it 'returns to_s when location does not respond to path' do
      loc = double('loc', to_s: 'unknown-location', respond_to?: false)
      allow(loc).to receive(:respond_to?).with(:path).and_return(false)

      result = serializer.format_location(loc)

      expect(result).to eq('unknown-location')
    end

    it 'strips root prefix from path' do
      loc = double('loc', respond_to?: false)
      allow(loc).to receive(:respond_to?).with(:path).and_return(true)
      allow(loc).to receive(:path).and_return('/tmp/test_root/app/models/user.rb')

      result = serializer.format_location(loc)

      expect(result).to eq('app/models/user.rb')
    end
  end

  describe '#declaration_type' do
    it 'detects class type' do
      decl = double('decl', class: double(name: 'Rubydex::ClassDeclaration'))

      result = serializer.declaration_type(decl)

      expect(result).to eq('class')
    end

    it 'detects module type' do
      decl = double('decl', class: double(name: 'Rubydex::ModuleDeclaration'))

      result = serializer.declaration_type(decl)

      expect(result).to eq('module')
    end

    it 'detects method type' do
      decl = double('decl', class: double(name: 'Rubydex::MethodDeclaration'))

      result = serializer.declaration_type(decl)

      expect(result).to eq('method')
    end

    it 'detects constant type' do
      decl = double('decl', class: double(name: 'Rubydex::ConstantDeclaration'))

      result = serializer.declaration_type(decl)

      expect(result).to eq('constant')
    end

    it 'falls back to declaration for unknown types' do
      decl = double('decl', class: double(name: 'Rubydex::SomethingElse'))

      result = serializer.declaration_type(decl)

      expect(result).to eq('declaration')
    end
  end
end
