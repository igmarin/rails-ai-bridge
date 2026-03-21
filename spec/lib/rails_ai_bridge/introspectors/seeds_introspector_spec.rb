# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspectors::SeedsIntrospector do
  let(:app) { Rails.application }
  let(:introspector) { described_class.new(app) }

  before do
    @db_dir = File.join(app.root.to_s, "db")
    FileUtils.mkdir_p(@db_dir)

    File.write(File.join(@db_dir, "seeds.rb"), <<~RUBY)
      # Default seeds
      if Rails.env.development?
        User.find_or_create_by!(email: "admin@example.com") do |u|
          u.name = "Admin"
        end

        10.times do
          Post.create!(
            title: Faker::Lorem.sentence,
            user: User.first
          )
        end
      end

      Dir[Rails.root.join("db/seeds/*.rb")].sort.each { |f| load f }
    RUBY

    FileUtils.mkdir_p(File.join(@db_dir, "seeds"))
    File.write(File.join(@db_dir, "seeds/categories.rb"), <<~RUBY)
      Category.find_or_create_by!(name: "General")
    RUBY
  end

  after do
    FileUtils.rm_f(File.join(@db_dir, "seeds.rb"))
    FileUtils.rm_rf(File.join(@db_dir, "seeds"))
  end

  describe "#call" do
    subject(:result) { introspector.call }

    it "analyzes seeds.rb" do
      seeds = result[:seeds_file]
      expect(seeds[:exists]).to be true
      expect(seeds[:uses_find_or_create]).to be true
      expect(seeds[:uses_create]).to be true
      expect(seeds[:uses_faker]).to be true
      expect(seeds[:environment_conditional]).to be true
      expect(seeds[:loads_directory]).to be true
    end

    it "discovers seed files in db/seeds/" do
      expect(result[:seed_files].size).to eq(1)
      expect(result[:seed_files].first[:name]).to eq("categories")
    end

    it "detects seeded models" do
      models = result[:models_seeded]
      expect(models).to include("User", "Post", "Category")
      expect(models).not_to include("Faker", "Rails", "Dir")
    end

    it "does not return an error" do
      expect(result[:error]).to be_nil
    end
  end
end
