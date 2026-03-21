# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspectors::AuthIntrospector do
  let(:introspector) { described_class.new(Rails.application) }

  describe "#call" do
    subject(:result) { introspector.call }

    it "does not return an error" do
      expect(result).not_to have_key(:error)
    end

    it "returns authentication as a hash" do
      expect(result[:authentication]).to be_a(Hash)
    end

    it "returns authorization as a hash" do
      expect(result[:authorization]).to be_a(Hash)
    end

    it "returns security as a hash" do
      expect(result[:security]).to be_a(Hash)
    end

    it "returns empty auth when no auth framework present" do
      expect(result[:authentication][:devise]).to be_nil
      expect(result[:authentication][:rails_auth]).to be_nil
    end

    it "returns empty authorization when no policies" do
      expect(result[:authorization][:pundit]).to be_nil
      expect(result[:authorization][:cancancan]).to be_nil
    end

    context "with has_secure_password in a model" do
      let(:fixture_model) { File.join(Rails.root, "app/models/account.rb") }

      before do
        File.write(fixture_model, <<~RUBY)
          class Account < ApplicationRecord
            has_secure_password
          end
        RUBY
      end

      after { FileUtils.rm_f(fixture_model) }

      it "detects has_secure_password with model name" do
        expect(result[:authentication][:has_secure_password]).to include("Account")
      end
    end

    context "with Devise in a model" do
      let(:fixture_model) { File.join(Rails.root, "app/models/admin.rb") }

      before do
        File.write(fixture_model, <<~RUBY)
          class Admin < ApplicationRecord
            devise :database_authenticatable, :registerable, :recoverable
          end
        RUBY
      end

      after { FileUtils.rm_f(fixture_model) }

      it "detects Devise models with modules" do
        devise_entry = result[:authentication][:devise]&.find { |d| d[:model] == "Admin" }
        expect(devise_entry).not_to be_nil
        expect(devise_entry[:matches].first).to include("database_authenticatable")
      end
    end

    context "with Pundit policies" do
      let(:policies_dir) { File.join(Rails.root, "app/policies") }

      before do
        FileUtils.mkdir_p(policies_dir)
        File.write(File.join(policies_dir, "post_policy.rb"), "class PostPolicy; end")
      end

      after { FileUtils.rm_rf(policies_dir) }

      it "detects Pundit policies" do
        expect(result[:authorization][:pundit]).to include("PostPolicy")
      end
    end

    context "with CSP initializer" do
      let(:csp_file) { File.join(Rails.root, "config/initializers/content_security_policy.rb") }

      before do
        FileUtils.mkdir_p(File.dirname(csp_file))
        File.write(csp_file, "# CSP config")
      end

      after { FileUtils.rm_f(csp_file) }

      it "detects CSP" do
        expect(result[:security][:csp]).to be true
      end
    end
  end
end
