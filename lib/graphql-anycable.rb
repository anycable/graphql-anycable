# frozen_string_literal: true

require "graphql"

require_relative "graphql/anycable/version"
require_relative "graphql/anycable/cleaner"
require_relative "graphql/anycable/config"
require_relative "graphql/anycable/railtie" if defined?(Rails)
require_relative "graphql/subscriptions/anycable_subscriptions"

module GraphQL
  module Anycable
    module_function

    def redis
      @redis ||= begin
        adapter = ::AnyCable.broadcast_adapter
        unless adapter.is_a?(::AnyCable::BroadcastAdapters::Redis)
          raise "Unsupported AnyCable adapter: #{adapter.class}. " \
                  "graphql-anycable works only with redis broadcast adapter."
        end
        ::AnyCable.broadcast_adapter.redis_conn
      end
    end
  end
end
