# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Tools::Query do
  let(:connection) { ActiveRecord::Base.connection }

  before do
    connection.create_table :rb_query_things, force: true do |t|
      t.string :name
      t.string :password
    end
    connection.execute "INSERT INTO rb_query_things (name, password) VALUES ('alpha', 'Bearer abc123secret')"
    connection.execute "INSERT INTO rb_query_things (name, password) VALUES ('beta', 'plainvalue')"
    connection.create_table :rb_query_variants, force: true do |t|
      t.string :password_digest
      t.string :encrypted_password
      t.string :secret_access_key
      t.string :author
      t.string :author_id
      t.string :authorization
      t.string :oauth_authorization_code
    end
    connection.execute 'INSERT INTO rb_query_variants ' \
                       '(password_digest, encrypted_password, secret_access_key, author, author_id, authorization, oauth_authorization_code) ' \
                       "VALUES ('digest-value', 'encrypted-value', 'key-value', 'Jane Doe', '7', 'Bearer x', 'code-1')"
  end

  after do
    connection.drop_table :rb_query_things, if_exists: true
    connection.drop_table :rb_query_variants, if_exists: true
  end

  def text_of(result)
    result.content.first[:text]
  end

  describe 'SQL allowlist guard' do
    it 'rejects empty SQL' do
      expect(text_of(described_class.call(sql: ''))).to include('error')
    end

    it 'rejects nil SQL' do
      expect(text_of(described_class.call(sql: nil))).to include('error')
    end

    it 'rejects multi-statement SQL' do
      expect(text_of(described_class.call(sql: 'SELECT 1; DROP TABLE x'))).to include('error')
    end

    it 'rejects two SELECT statements separated by a semicolon' do
      expect(text_of(described_class.call(sql: 'SELECT 1; SELECT 2'))).to include('error')
    end

    it 'rejects WITH (CTE) queries in v1' do
      expect(text_of(described_class.call(sql: 'WITH t AS (SELECT 1) SELECT * FROM t'))).to include('error')
    end

    %w[INSERT UPDATE DELETE ALTER CREATE PRAGMA ATTACH DROP TRUNCATE].each do |verb|
      it "rejects #{verb} statements" do
        sql = "#{verb} #{if verb == 'INSERT'
                           'INTO rb_query_things (name) VALUES (1)'
                         else
                           (verb == 'ATTACH' ? 'DATABASE x AS y' : 'TABLE rb_query_things').to_s
                         end}"
        expect(text_of(described_class.call(sql: sql))).to include('error')
      end
    end

    it 'rejects FOR UPDATE locking clauses' do
      expect(text_of(described_class.call(sql: 'SELECT name FROM rb_query_things FOR UPDATE'))).to include('error')
    end

    it 'rejects FOR SHARE locking clauses' do
      expect(text_of(described_class.call(sql: 'SELECT name FROM rb_query_things FOR SHARE'))).to include('error')
    end

    it 'rejects MySQL LOCK IN SHARE MODE locking clauses' do
      expect(text_of(described_class.call(sql: 'SELECT name FROM rb_query_things LOCK IN SHARE MODE'))).to include('error')
    end

    it 'rejects SELECT INTO (table creation)' do
      expect(text_of(described_class.call(sql: 'SELECT name INTO dump_table FROM rb_query_things'))).to include('error')
    end

    it 'rejects SELECT ... INTO OUTFILE' do
      expect(text_of(described_class.call(sql: "SELECT name INTO OUTFILE '/tmp/dump.csv' FROM rb_query_things"))).to include('error')
    end

    it 'runs a plain SELECT' do
      expect(text_of(described_class.call(sql: 'SELECT name FROM rb_query_things'))).to include('alpha')
    end

    %w[EXPLAIN SHOW CALL DO COPY VALUES].each do |verb|
      it "rejects #{verb} as a non-SELECT verb" do
        sql = case verb
              when 'EXPLAIN' then 'EXPLAIN SELECT 1'
              when 'SHOW' then 'SHOW TABLES'
              when 'CALL' then 'CALL some_proc()'
              when 'DO' then 'DO $$ BEGIN NULL; END $$'
              when 'COPY' then 'COPY rb_query_things TO STDOUT'
              else 'VALUES (1)'
              end
        expect(text_of(described_class.call(sql: sql))).to include('error')
      end
    end

    it 'rejects a leading SQL comment even when the rest is SELECT' do
      expect(text_of(described_class.call(sql: '/* x */ SELECT name FROM rb_query_things'))).to include('error')
    end
  end

  describe 'row cap' do
    it 'caps results at MAX_ROWS (100)' do
      120.times { connection.execute "INSERT INTO rb_query_things (name, password) VALUES ('row', 'v')" }
      payload = JSON.parse(text_of(described_class.call(sql: 'SELECT name FROM rb_query_things', detail: 'full')))
      expect(payload.fetch('rows').size).to eq(100)
      expect(payload['truncated']).to be_truthy
    end

    it 'signals truncation when rows exceed the limit' do
      5.times { connection.execute "INSERT INTO rb_query_things (name, password) VALUES ('r', 'v')" }
      payload = JSON.parse(text_of(described_class.call(sql: 'SELECT name FROM rb_query_things', row_limit: 3)))
      expect(payload['truncated']).to be_truthy
      expect(payload['rows'].size).to eq(3)
    end
  end

  describe 'timeout mechanism' do
    it 'returns a timeout error when the execution exceeds the statement timeout' do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      expect(text_of(described_class.call(sql: 'SELECT name FROM rb_query_things'))).to include('timed out')
    end

    it 'sets PostgreSQL statement_timeout instead of relying only on Timeout.timeout' do
      connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter, adapter_name: 'PostgreSQL')
      allow(ApplicationRecord).to receive(:connection).and_return(connection)
      allow(connection).to receive(:transaction).with(requires_new: true).and_yield
      allow(connection).to receive(:execute)
      allow(connection).to receive(:select_all).and_return(ActiveRecord::Result.new(['x'], []))
      allow(Timeout).to receive(:timeout)

      described_class.call(sql: 'SELECT 1')

      expect(connection).to have_received(:execute).with('SET LOCAL statement_timeout = 5000')
      expect(connection).to have_received(:execute).with('SET TRANSACTION READ ONLY')
      expect(Timeout).not_to have_received(:timeout)
    end

    it 'returns a timeout error when PostgreSQL cancels the statement' do
      connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter, adapter_name: 'PostgreSQL')
      allow(ApplicationRecord).to receive(:connection).and_return(connection)
      allow(connection).to receive(:transaction).with(requires_new: true).and_yield
      allow(connection).to receive(:execute)
      allow(connection).to receive(:select_all)
        .and_raise(ActiveRecord::QueryCanceled, 'canceling statement due to statement timeout')

      expect(text_of(described_class.call(sql: 'SELECT 1'))).to include('timed out')
    end
  end

  describe 'credential redaction' do
    it 'redacts values under credential-like columns via MessageSanitizer' do
      result = described_class.call(sql: 'SELECT name, password FROM rb_query_things')
      expect(text_of(result)).to include('[redacted]')
      expect(text_of(result)).not_to include('Bearer abc123secret')
    end
  end

  describe 'credential column redaction variants' do
    it 'redacts password_digest values' do
      result = described_class.call(sql: 'SELECT password_digest FROM rb_query_variants')
      expect(text_of(result)).to include('[redacted]')
    end

    it 'redacts encrypted_password values' do
      result = described_class.call(sql: 'SELECT encrypted_password FROM rb_query_variants')
      expect(text_of(result)).to include('[redacted]')
    end

    it 'redacts secret_access_key values' do
      result = described_class.call(sql: 'SELECT secret_access_key FROM rb_query_variants')
      expect(text_of(result)).to include('[redacted]')
    end

    it 'does not redact non-credential columns like author' do
      result = described_class.call(sql: 'SELECT author FROM rb_query_variants')
      expect(text_of(result)).not_to include('[redacted]')
      expect(text_of(result)).to include('Jane Doe')
    end

    it 'does not redact author_id metadata columns' do
      result = described_class.call(sql: 'SELECT author_id FROM rb_query_variants')
      expect(text_of(result)).not_to include('[redacted]')
    end

    it 'still redacts authorization columns' do
      result = described_class.call(sql: 'SELECT authorization FROM rb_query_variants')
      expect(text_of(result)).to include('[redacted]')
    end

    it 'still redacts oauth_authorization_code columns' do
      result = described_class.call(sql: 'SELECT oauth_authorization_code FROM rb_query_variants')
      expect(text_of(result)).to include('[redacted]')
    end
  end

  describe 'detail levels' do
    it 'summary returns columns and row count only' do
      payload = JSON.parse(text_of(described_class.call(sql: 'SELECT name, password FROM rb_query_things', detail: 'summary')))
      expect(payload['rows']).to be_nil
      expect(payload['columns']).to match_array(%w[name password])
    end
  end

  describe 'error contract for invalid SQL' do
    it 'returns a JSON payload with an error key for bad SQL' do
      payload = JSON.parse(text_of(described_class.call(sql: 'SELECT nope FROM missing_table_xyz')))
      expect(payload).to have_key('error')
    end
  end

  describe 'annotations' do
    it 'declares destructive: false, read_only: true, idempotent: true' do
      expect(described_class.annotations.destructive_hint).to be(false)
      expect(described_class.annotations.read_only_hint).to be(true)
      expect(described_class.annotations.idempotent_hint).to be(true)
    end
  end
end
