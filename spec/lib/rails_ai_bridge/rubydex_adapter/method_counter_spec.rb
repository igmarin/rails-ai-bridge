# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::RubydexAdapter::MethodCounter do
  let(:root) { '/tmp/test_root' }
  let(:serializer) { RailsAiBridge::RubydexAdapter::Serializer.new(root) }
  let(:counter) { described_class.new(serializer: serializer) }

  describe '#count' do
    it 'returns 0 for an empty array' do
      expect(counter.count([])).to eq(0)
    end

    it 'counts definitions whose names contain parentheses as methods' do
      defn = double('defn', name: 'save()', respond_to?: false)
      decl = double('decl', respond_to?: false)
      allow(decl).to receive(:respond_to?).with(:definitions).and_return(true)
      allow(decl).to receive(:definitions).and_return([defn])

      expect(counter.count([decl])).to eq(1)
    end

    it 'counts definitions classified as method type by the serializer' do
      method_class = double(name: 'Rubydex::MethodDeclaration')
      defn = double('defn', name: 'process', class: method_class)
      decl = double('decl', respond_to?: false)
      allow(decl).to receive(:respond_to?).with(:definitions).and_return(true)
      allow(decl).to receive(:definitions).and_return([defn])

      expect(counter.count([decl])).to eq(1)
    end

    it 'does not count definitions that are neither method-like' do
      class_class = double(name: 'Rubydex::ClassDeclaration')
      defn = double('defn', name: 'UserModel', class: class_class)
      decl = double('decl', respond_to?: false)
      allow(decl).to receive(:respond_to?).with(:definitions).and_return(true)
      allow(decl).to receive(:definitions).and_return([defn])

      expect(counter.count([decl])).to eq(0)
    end

    it 'skips declarations that do not respond to definitions' do
      decl = double('decl', respond_to?: false)
      allow(decl).to receive(:respond_to?).with(:definitions).and_return(false)

      expect(counter.count([decl])).to eq(0)
    end

    it 'returns 0 when a definition lookup raises' do
      defn = double('defn')
      allow(defn).to receive(:name).and_raise(StandardError, 'boom')
      decl = double('decl', respond_to?: false)
      allow(decl).to receive(:respond_to?).with(:definitions).and_return(true)
      allow(decl).to receive(:definitions).and_return([defn])

      expect(counter.count([decl])).to eq(0)
    end

    it 'returns 0 when definition count raises' do
      decl = double('decl', respond_to?: false)
      allow(decl).to receive(:respond_to?).with(:definitions).and_return(true)
      allow(decl).to receive(:definitions).and_raise(StandardError, 'boom')

      expect(counter.count([decl])).to eq(0)
    end

    it 'sums methods across multiple declarations' do
      defn1 = double('defn1', name: 'save()', respond_to?: false)
      defn2 = double('defn2', name: 'update()', respond_to?: false)
      decl1 = double('decl1', respond_to?: false)
      decl2 = double('decl2', respond_to?: false)
      allow(decl1).to receive(:respond_to?).with(:definitions).and_return(true)
      allow(decl1).to receive(:definitions).and_return([defn1])
      allow(decl2).to receive(:respond_to?).with(:definitions).and_return(true)
      allow(decl2).to receive(:definitions).and_return([defn2])

      expect(counter.count([decl1, decl2])).to eq(2)
    end
  end
end
