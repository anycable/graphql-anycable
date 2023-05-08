# frozen_string_literal: true

ENV["GRAPHQL_ANYCABLE_USE_CLIENT_PROVIDED_UNIQ_ID"] ||= "false"

require "bundler/setup"
require "graphql/anycable"
require "pry"

require_relative "support/graphql_schema"
require_relative "redis_helper"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.filter_run :focus
  config.run_all_when_everything_filtered = true

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec

  Kernel.srand config.seed
  config.order = :random
end
