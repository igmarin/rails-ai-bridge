# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Introspectors::ModelIntrospector::SourceMacroExtractor do
  def extract(source)
    described_class.new(source).call
  end

  describe '#call' do
    it 'returns an empty hash for source with no macros' do
      expect(extract("class Foo\nend\n")).to eq({})
    end

    it 'detects has_secure_password as true' do
      expect(extract('has_secure_password')).to eq(has_secure_password: true)
    end

    it 'extracts symbol args from encrypts' do
      result = extract('encrypts :ssn, :token, deterministic: true')
      expect(result[:encrypts]).to eq(%w[ssn token])
    end

    it 'extracts symbol args from normalizes' do
      result = extract("normalizes :email, with: ->(e) { e.downcase }")
      expect(result[:normalizes]).to eq(%w[email])
    end

    it 'extracts has_one_attached and has_many_attached names' do
      source = <<~RUBY
        has_one_attached :avatar
        has_many_attached :photos
      RUBY
      result = extract(source)
      expect(result[:has_one_attached]).to eq(%w[avatar])
      expect(result[:has_many_attached]).to eq(%w[photos])
    end

    it 'extracts has_rich_text names' do
      expect(extract('has_rich_text :body')[:has_rich_text]).to eq(%w[body])
    end

    it 'detects broadcasts macros uniquely' do
      source = <<~RUBY
        broadcasts_to :board
        broadcasts_refreshes_to :board
        broadcasts
      RUBY
      expect(extract(source)[:broadcasts]).to match_array(
        %w[broadcasts_to broadcasts_refreshes_to broadcasts]
      )
    end

    it 'extracts generates_token_for names' do
      expect(extract('generates_token_for :password_reset')[:generates_token_for])
        .to eq(%w[password_reset])
    end

    it 'extracts serialize and store accessors' do
      source = <<~RUBY
        serialize :preferences
        store_accessor :settings
        store :metadata
      RUBY
      result = extract(source)
      expect(result[:serialize]).to eq(%w[preferences])
      expect(result[:store]).to match_array(%w[settings metadata])
    end

    it 'extracts delegations with methods and target' do
      result = extract('delegate :name, :email, to: :user')
      expect(result[:delegations]).to eq([{ methods: %w[name email], to: 'user' }])
    end

    it 'omits :delegations when none are present' do
      expect(extract('has_secure_password')).not_to have_key(:delegations)
    end

    it 'extracts delegate_missing_to target' do
      expect(extract('delegate_missing_to :record')[:delegate_missing_to]).to eq('record')
    end

    it 'omits :delegate_missing_to when not present' do
      expect(extract('has_secure_password')).not_to have_key(:delegate_missing_to)
    end

    it 'removes empty array values' do
      # encrypts pattern requires `:` after; if absent it should not be added.
      expect(extract('encrypts')).not_to have_key(:encrypts)
    end

    it 'returns {} when the source raises during scanning' do
      bad = instance_double(String)
      allow(bad).to receive(:match?).and_raise(StandardError)
      expect(described_class.new(bad).call).to eq({})
    end
  end
end
