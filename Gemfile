# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in graphql-anycable.gemspec
gemspec

gem "graphql", ENV.fetch("GRAPHQL_RUBY_VERSION", "~> 2.3")
gem "anycable", ENV.fetch("ANYCABLE_VERSION", "~> 1.5")
gem "anycable-rails", ENV.fetch("ANYCABLE_RAILS_VERSION", "~> 1.5")
gem "rack", "< 3.0" if /1\.4/.match?(ENV.fetch("ANYCABLE_VERSION", "~> 1.5"))

gem "ostruct"

group :development, :test do
  gem "debug", platforms: [:mri] unless ENV["CI"]
end

group :development do
  eval_gemfile "gemfiles/rubocop.gemfile"
end
