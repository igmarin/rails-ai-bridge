# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiBridge::ViewFileAnalyzer do
  let(:root) { Rails.root }

  describe ".call" do
    it "returns metadata and content for a valid path under app/views" do
      result = described_class.call(root: root, relative_path: "posts/index.html.erb")

      expect(result[:path]).to eq("posts/index.html.erb")
      expect(result[:template_engine]).to eq("erb")
      expect(result[:partial]).to be(false)
      expect(result[:content]).to include("<h1>Posts</h1>")
    end

    it "raises SecurityError for parent-directory traversal" do
      expect do
        described_class.call(root: root, relative_path: "../../../etc/passwd")
      end.to raise_error(SecurityError, /Path not allowed/)
    end

    it "raises SecurityError for absolute paths outside app/views" do
      expect do
        described_class.call(root: root, relative_path: "/etc/passwd")
      end.to raise_error(SecurityError, /Path not allowed/)
    end

    it "raises Errno::ENOENT for a path inside app/views that does not exist" do
      expect do
        described_class.call(root: root, relative_path: "missing/template.html.erb")
      end.to raise_error(Errno::ENOENT)
    end
  end
end
