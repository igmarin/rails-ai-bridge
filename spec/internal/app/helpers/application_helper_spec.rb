# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ApplicationHelper do
  describe '#page_title' do
    it 'escapes HTML in the title' do
      result = ApplicationController.helpers.page_title("<script>alert('xss')</script>")
      expect(result).to include('&lt;script&gt;')
      expect(result).not_to include('<script>')
    end

    it 'uses the tag helper instead of content_tag' do
      source = File.read(Rails.root.join('app/helpers/application_helper.rb').to_s)
      expect(source).to include('tag.h1(title)')
      expect(source).not_to include('content_tag')
    end
  end
end
