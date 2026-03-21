# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::Introspectors::SchemaIntrospector do
  let(:app) { double("app", root: Pathname.new(fixture_path)) }
  let(:fixture_path) { File.expand_path("../../fixtures", __FILE__) }
  let(:introspector) { described_class.new(app) }

  describe "#call" do
    context "when ActiveRecord is not connected and no schema.rb" do
      before do
        allow(introspector).to receive(:active_record_connected?).and_return(false)
      end

      it "returns an error" do
        result = introspector.call
        expect(result[:error]).to include("No schema.rb")
      end
    end

    context "with a valid schema.rb fixture" do
      before do
        allow(introspector).to receive(:active_record_connected?).and_return(false)

        # Create fixture schema.rb
        db_dir = File.join(fixture_path, "db")
        FileUtils.mkdir_p(db_dir)
        File.write(File.join(db_dir, "schema.rb"), <<~RUBY)
          ActiveRecord::Schema[7.1].define(version: 2024_01_15_000000) do
            create_table "users" do |t|
              t.string "email"
              t.string "name"
              t.integer "role"
              t.timestamps
            end

            create_table "posts" do |t|
              t.string "title"
              t.text "body"
              t.references "user"
              t.timestamps
            end
          end
        RUBY
      end

      after do
        FileUtils.rm_rf(File.join(fixture_path, "db"))
      end

      it "falls back to static schema.rb parsing" do
        result = introspector.call
        expect(result[:adapter]).to eq("static_parse")
        expect(result[:note]).to include("no DB connection")
      end

      it "parses tables from schema.rb" do
        result = introspector.call
        expect(result[:tables]).to have_key("users")
        expect(result[:tables]).to have_key("posts")
        expect(result[:total_tables]).to eq(2)
      end

      it "extracts column names and types" do
        result = introspector.call
        user_cols = result[:tables]["users"][:columns]
        expect(user_cols).to include(a_hash_including(name: "email", type: "string"))
        expect(user_cols).to include(a_hash_including(name: "role", type: "integer"))
      end
    end

    context "schema version parsing" do
      before do
        allow(introspector).to receive(:active_record_connected?).and_return(true)
        allow(introspector).to receive(:adapter_name).and_return("postgresql")
        allow(introspector).to receive(:table_names).and_return([])
        allow(introspector).to receive(:extract_tables).and_return({})
      end

      it "parses full schema version with underscores" do
        db_dir = File.join(fixture_path, "db")
        FileUtils.mkdir_p(db_dir)
        File.write(File.join(db_dir, "schema.rb"), <<~RUBY)
          ActiveRecord::Schema[7.1].define(version: 2024_01_15_123456) do
          end
        RUBY

        result = introspector.call
        expect(result[:schema_version]).to eq("20240115123456")
      ensure
        FileUtils.rm_rf(db_dir)
      end
    end
  end
end
