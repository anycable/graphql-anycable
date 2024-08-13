# frozen_string_literal: true

require "graphql"

require_relative "graphql/anycable/version"
require_relative "graphql/anycable/cleaner"
require_relative "graphql/anycable/config"
require_relative "graphql/anycable/railtie" if defined?(Rails)
require_relative "graphql/anycable/stats"
require_relative "graphql/subscriptions/anycable_subscriptions"

module GraphQL
  module AnyCable
    class << self
      def use(schema, **opts)
        schema.use(GraphQL::Subscriptions::AnyCableSubscriptions, **opts)
      end

      def stats(**opts)
        Stats.new(**opts).collect
      end

      def redis=(connector)
        @redis_connector = if connector.is_a?(::Proc)
          connector
        else
          ->(&block) { block.call connector }
        end
      end

      def with_redis(&block)
        @redis_connector || default_redis_connector
        @redis_connector.call { |conn| block.call(conn) }
      end

      def config
        @config ||= Config.new
      end

      def configure
        yield(config) if block_given?
      end

      private

      def default_redis_connector
        adapter = ::AnyCable.broadcast_adapter
        unless adapter.is_a?(::AnyCable::BroadcastAdapters::Redis)
          raise "Unsupported AnyCable adapter: #{adapter.class}. " \
                "Please, configure Redis connector manually:\n\n" \
                "  GraphQL::AnyCable.configure do |config|\n" \
                "    config.redis = Redis.new(url: 'redis://localhost:6379/0')\n" \
                "  end\n"
        end

        self.redis = ::AnyCable.broadcast_adapter.redis_conn
      end
    end
  end
end
