# frozen_string_literal: true

require "graphql"

require_relative "graphql/anycable/version"
require_relative "graphql/anycable/config"
require_relative "graphql/anycable/railtie" if defined?(Rails)
require_relative "graphql/subscriptions/anycable_subscriptions"

module Graphql
  module Anycable
  end
end
