# frozen_string_literal: true

# Helpers shared by the rake-task specs.
module RakeSpecHelpers
  # Runs the block with the given env vars set, restoring prior values (or
  # deleting them when they were unset) afterwards. Keeps examples isolated
  # from host/CI environment variables.
  #
  # @param env [Hash{String, Symbol => String}] env vars to set for the block
  # @yield the example body
  # @return [void]
  def with_env(env)
    previous = env.each_key.to_h { |key| [key.to_s, ENV.fetch(key.to_s, nil)] }
    env.each { |key, value| ENV[key.to_s] = value }
    yield
  ensure
    previous.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  # Rake files are evaluated at the top level, so task bodies resolve DSL
  # methods such as `sh` on the main object rather than on the example instance.
  #
  # @return [Object] the top-level main object that rake task bodies execute as
  def rake_top_level
    TOPLEVEL_BINDING.eval('self')
  end
end

RSpec.configure { |config| config.include RakeSpecHelpers }
