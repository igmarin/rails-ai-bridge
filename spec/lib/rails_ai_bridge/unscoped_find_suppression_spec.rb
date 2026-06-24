# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Unscoped-find false-positive suppressions in test controllers' do
  def project_root
    Pathname.new(__dir__).join('..', '..', '..').expand_path
  end

  def controller_source(relative_path)
    File.read(project_root.join(relative_path).to_s)
  end

  it 'documents the unscoped-find suppression in PostsController' do
    source = controller_source('spec/internal/app/controllers/posts_controller.rb')
    expect(source).to include('nosemgrep')
    expect(source).to include('unscoped-find')
    expect(source).to include('Post.find(params[:id])')
  end

  it 'documents the unscoped-find suppression in UsersController' do
    source = controller_source('spec/internal/app/controllers/users_controller.rb')
    expect(source).to include('nosemgrep')
    expect(source).to include('unscoped-find')
    expect(source).to include('User.find(params[:id])')
  end
end
