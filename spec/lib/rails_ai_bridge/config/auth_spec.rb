# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Config::Auth do
  subject(:auth) { described_class.new }

  it 'defaults http_mcp_token to nil' do
    expect(auth.http_mcp_token).to be_nil
  end

  it 'defaults allow_auto_mount_in_production to false' do
    expect(auth.allow_auto_mount_in_production).to be(false)
  end

  it 'defaults mcp_token_resolver to nil' do
    expect(auth.mcp_token_resolver).to be_nil
  end

  it 'defaults mcp_jwt_decoder to nil' do
    expect(auth.mcp_jwt_decoder).to be_nil
  end

  it 'allows setting http_mcp_token' do
    auth.http_mcp_token = 'secret'
    expect(auth.http_mcp_token).to eq('secret')
  end

  it 'allows setting mcp_token_resolver' do
    resolver = ->(t) { t == 'ok' }
    auth.mcp_token_resolver = resolver
    expect(auth.mcp_token_resolver).to eq(resolver)
  end

  it 'allows setting mcp_jwt_decoder' do
    decoder = ->(t) { { sub: t } }
    auth.mcp_jwt_decoder = decoder
    expect(auth.mcp_jwt_decoder).to eq(decoder)
  end
end
