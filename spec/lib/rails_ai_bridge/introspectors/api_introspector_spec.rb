# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspectors::ApiIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe "#call" do
    subject(:result) { introspector.call }

    it "does not return an error" do
      expect(result).not_to have_key(:error)
    end

    it "returns api_only as false for standard app" do
      expect(result[:api_only]).to be false
    end

    it "returns serializers as a hash" do
      expect(result[:serializers]).to be_a(Hash)
    end

    it "returns api versioning array" do
      expect(result[:api_versioning]).to be_an(Array)
    end

    it "returns rate limiting as empty hash when no rate limiting" do
      expect(result[:rate_limiting]).to be_a(Hash)
    end

    it "detects v1 API versioning from directory structure" do
      expect(result[:api_versioning]).to include("v1")
    end

    it "returns nil for graphql when no app/graphql dir" do
      expect(result[:graphql]).to be_nil
    end

    context "with a serializer directory" do
      let(:serializers_dir) { File.join(Rails.root, "app/serializers") }
      let(:serializer_file) { File.join(serializers_dir, "post_serializer.rb") }

      before do
        FileUtils.mkdir_p(serializers_dir)
        File.write(serializer_file, <<~RUBY)
          class PostSerializer
            def call(post)
              { id: post.id, title: post.title }
            end
          end
        RUBY
      end

      after { FileUtils.rm_rf(serializers_dir) }

      it "detects serializer classes" do
        expect(result[:serializers][:serializer_classes]).to include("PostSerializer")
      end
    end

    context "with rack-attack initializer" do
      let(:init_path) { File.join(Rails.root, "config/initializers/rack_attack.rb") }

      before do
        FileUtils.mkdir_p(File.dirname(init_path))
        File.write(init_path, "# Rack::Attack config")
      end

      after { FileUtils.rm_f(init_path) }

      it "detects rack_attack rate limiting" do
        expect(result[:rate_limiting]).to eq({ rack_attack: true })
      end
    end
  end
end
