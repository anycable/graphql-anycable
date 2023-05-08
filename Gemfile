# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in graphql-anycable.gemspec
gemspec

gem "graphql",  ENV.fetch("GRAPHQL_RUBY_VERSION", "~> 1.12")
gem "anycable", ENV.fetch("ANYCABLE_VERSION", "~> 1.0")
gem "anycable-rails", ENV.fetch("ANYCABLE_RAILS_VERSION", "~> 1.3")

group :development, :test do
  gem "pry"
  gem "pry-byebug", platform: :mri

  gem 'rubocop', '~> 1.50', '>= 1.50.2', require: false
  gem 'rubocop-rspec', '~> 2.20', require: false
end
