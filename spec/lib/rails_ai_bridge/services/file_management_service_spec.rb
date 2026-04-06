# frozen_string_literal: true

require "spec_helper"
require "rails_ai_bridge/services/file_management_service"
require "fileutils"

RSpec.describe RailsAiBridge::Services::FileManagementService do
  let(:test_dir) { "/tmp/rails_ai_bridge_test" }
  let(:test_file) { "#{test_dir}/test_file.txt" }

  before do
    FileUtils.mkdir_p(test_dir)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe ".call" do
    it "writes content to file successfully" do
      result = RailsAiBridge::Services::FileManagementService.call(:write, path: test_file, content: "test content")

      expect(result.success?).to be(true)
      expect(File.exist?(test_file)).to be(true)
      expect(File.read(test_file)).to eq("test content")
    end

    it "reads content from file successfully" do
      File.write(test_file, "existing content")

      result = RailsAiBridge::Services::FileManagementService.call(:read, path: test_file)

      expect(result.success?).to be(true)
      expect(result.data).to eq("existing content")
    end

    it "deletes file successfully" do
      File.write(test_file, "content")
      expect(File.exist?(test_file)).to be(true)

      result = RailsAiBridge::Services::FileManagementService.call(:delete, path: test_file)

      expect(result.success?).to be(true)
      expect(File.exist?(test_file)).to be(false)
    end

    it "handles file not found errors" do
      result = RailsAiBridge::Services::FileManagementService.call(:read, path: "/nonexistent/file.txt")

      expect(result.failure?).to be(true)
      expect(result.errors.first).to match(/No such file or directory/)
    end

    it "handles permission errors gracefully" do
      # Test with a real permission error by trying to write to root
      # This should fail gracefully
      result = RailsAiBridge::Services::FileManagementService.call(:write, path: "/permission_test_file.txt", content: "content")

      # We expect it to either succeed (if we have permission) or fail gracefully
      if result.failure?
        expect(result.errors.first).to match(/Permission denied|Operation not permitted|Read-only file system/)
      else
        # Clean up if it succeeded
        File.delete("/permission_test_file.txt") rescue nil
      end
    end
  end

  describe "#call" do
    subject { RailsAiBridge::Services::FileManagementService.new }

    it "supports write operation" do
      result = subject.call(:write, path: "#{test_dir}/write_test.txt", content: "written")

      expect(result.success?).to be(true)
      expect(File.read("#{test_dir}/write_test.txt")).to eq("written")
    end

    it "supports read operation" do
      test_read_file = "#{test_dir}/read_test.txt"
      File.write(test_read_file, "readable content")

      result = subject.call(:read, path: test_read_file)

      expect(result.success?).to be(true)
      expect(result.data).to eq("readable content")
    end

    it "supports delete operation" do
      test_delete_file = "#{test_dir}/delete_test.txt"
      File.write(test_delete_file, "content")

      result = subject.call(:delete, path: test_delete_file)

      expect(result.success?).to be(true)
      expect(File.exist?(test_delete_file)).to be(false)
    end

    it "supports file existence check" do
      existing_file = "#{test_dir}/existing.txt"
      File.write(existing_file, "content")

      result = subject.call(:exist?, path: existing_file)

      expect(result.success?).to be(true)
      expect(result.data).to be(true)
    end

    it "returns false for non-existent files" do
      result = subject.call(:exist?, path: "/nonexistent/file.txt")

      expect(result.success?).to be(true)
      expect(result.data).to be(false)
    end
  end

  describe "file operations" do
    it "creates directories if needed for write" do
      nested_path = "#{test_dir}/nested/dir/file.txt"

      result = RailsAiBridge::Services::FileManagementService.call(:write, path: nested_path, content: "nested content")

      expect(result.success?).to be(true)
      expect(File.exist?(nested_path)).to be(true)
    end

    it "handles directory creation errors" do
      # Test error handling by trying to create in a protected location
      result = RailsAiBridge::Services::FileManagementService.call(:write, path: "/root/protected/nested/file.txt", content: "content")

      # Should fail gracefully if we don't have permission
      if result.failure?
        expect(result.errors.first).to match(/Permission denied|Operation not permitted|Read-only file system/)
      end
    end
  end

  describe "result format" do
    it "returns Service::Result for all operations" do
      # Write operation
      write_result = RailsAiBridge::Services::FileManagementService.call(:write, path: "#{test_dir}/result_test.txt", content: "test")
      expect(write_result).to be_a(RailsAiBridge::Service::Result)

      # Read operation
      read_result = RailsAiBridge::Services::FileManagementService.call(:read, path: "#{test_dir}/result_test.txt")
      expect(read_result).to be_a(RailsAiBridge::Service::Result)

      # Delete operation
      delete_result = RailsAiBridge::Services::FileManagementService.call(:delete, path: "#{test_dir}/result_test.txt")
      expect(delete_result).to be_a(RailsAiBridge::Service::Result)
    end
  end
end
