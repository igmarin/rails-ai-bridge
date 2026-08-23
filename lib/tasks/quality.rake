# frozen_string_literal: true

require 'open3'

namespace :docs do
  desc 'Fail when YARD documentation falls below the configured floor'
  task :yard do
    output, status = Open3.capture2e('yard', 'stats', '--list-undoc')
    print output

    documented = output[/([0-9]+(?:\.[0-9]+)?)% documented/, 1]&.to_f
    minimum = ENV.fetch('YARD_MINIMUM_PERCENT', '90').to_f
    abort "YARD documentation is below #{minimum}%" unless status.success? && documented && documented >= minimum
  end
end

namespace :quality do
  desc 'Run Reek against the library'
  task :reek do
    sh 'reek', 'lib/'
  end
end
