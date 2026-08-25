# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::MessageSanitizer do
  describe '.sanitize' do
    it 'redacts http URLs' do
      result = described_class.sanitize('connection to http://secret.example.com/path failed')

      expect(result).to include('[redacted]')
      expect(result).not_to include('secret.example.com')
    end

    it 'redacts https URLs with query strings' do
      result = described_class.sanitize('failed to reach https://api.example.com/v1?token=abc123')

      expect(result).to include('[redacted]')
      expect(result).not_to include('api.example.com')
      expect(result).not_to include('token=abc123')
    end

    it 'redacts ssh, git, file, ftp, sftp, ws, and wss URLs' do
      %w[ssh git file ftp sftp ws wss].each do |scheme|
        result = described_class.sanitize("connection via #{scheme}://host.example.com/path")

        expect(result).to include('[redacted]')
        expect(result).not_to include('host.example.com')
      end
    end

    it 'redacts database URLs (postgres, mysql, redis)' do
      %w[postgres mysql redis mongodb].each do |scheme|
        result = described_class.sanitize("connecting to #{scheme}://user:pass@db.example.com:5432/mydb")

        expect(result).to include('[redacted]')
        expect(result).not_to include('db.example.com')
        expect(result).not_to include('user:pass')
      end
    end

    it 'redacts git@ SSH URIs' do
      result = described_class.sanitize('clone from git@github.com:user/repo.git')

      expect(result).to include('[redacted]')
      expect(result).not_to include('github.com')
    end

    it 'redacts absolute paths after whitespace' do
      result = described_class.sanitize('error at /etc/secrets/config.yml')

      expect(result).to include('[redacted]')
      expect(result).not_to include('/etc/secrets')
    end

    it 'redacts absolute paths at start of string' do
      result = described_class.sanitize('/usr/local/bin/config.json not found')

      expect(result).to include('[redacted]')
      expect(result).not_to include('/usr/local')
    end

    it 'redacts paths inside quotes' do
      result = described_class.sanitize("No such file or directory - '/etc/secrets/config.yml'")

      expect(result).to include('[redacted]')
      expect(result).not_to include('/etc/secrets')
    end

    it 'redacts paths inside parentheses' do
      result = described_class.sanitize('failed to open (/var/log/app.log) for reading')

      expect(result).to include('[redacted]')
      expect(result).not_to include('/var/log')
    end

    it 'redacts Windows paths' do
      result = described_class.sanitize('failed to read C:\\Users\\admin\\secrets.txt')

      expect(result).to include('[redacted]')
      expect(result).not_to include('Users')
    end

    it 'does not redact harmless text like 24/7 or and/or' do
      result = described_class.sanitize('service is up 24/7 and/or available')

      expect(result).to include('24/7')
      expect(result).to include('and/or')
    end

    it 'handles nil messages gracefully' do
      expect(described_class.sanitize(nil)).to eq('')
    end
  end
end
