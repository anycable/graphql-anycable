# frozen_string_literal: true

require "graphql"

require_relative "graphql/anycable/version"
require_relative "graphql/anycable/config"
require_relative "graphql/anycable/subscription_stores/redis"
require_relative "graphql/anycable/cleaner"
require_relative "graphql/anycable/railtie" if defined?(Rails)
require_relative "graphql/anycable/stats"
require_relative "graphql/subscriptions/anycable_subscriptions"

module GraphQL
  module AnyCable
    class << self
      attr_writer :subscription_store

      def use(schema, **opts)
        schema.use(GraphQL::Subscriptions::AnyCableSubscriptions, **opts)
      end

      def stats(**opts)
        Stats.new(**opts).collect
      end

      def redis
        warn "Usage of `GraphQL::AnyCable.redis` is deprecated. Instead of `GraphQL::AnyCable.redis.whatever` use `GraphQL::AnyCable.with_redis { |redis| redis.whatever }`"
        @redis ||= with_redis { |conn| conn }
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
        @redis_connector.call(&block)
      end

      def register_subscription_store(name, store = nil, &factory)
        unless store || factory
          raise ArgumentError, "Provide a subscription store instance or a factory block"
        end

        subscription_store_registry[name.to_sym] = factory || -> { store }
      end

      def subscription_store
        @subscription_store ||= default_subscription_store
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
        redis_adapter = defined?(::AnyCable::BroadcastAdapters::Redis) && ::AnyCable::BroadcastAdapters::Redis
        unless redis_adapter && adapter.is_a?(redis_adapter)
          raise "Unsupported AnyCable adapter: #{adapter.class}. " \
                "Please, configure Redis connector manually:\n\n" \
                "  GraphQL::AnyCable.configure do |config|\n" \
                "    config.redis = Redis.new(url: 'redis://localhost:6379/0')\n" \
                "  end\n"
        end

        self.redis = ::AnyCable.broadcast_adapter.redis_conn
      end

      def default_subscription_store
        adapter = config.subscription_store&.to_sym || inferred_subscription_store
        factory = subscription_store_registry[adapter]
        return build_subscription_store(factory) if factory

        raise "Unsupported GraphQL::AnyCable subscription store: #{adapter.inspect}. " \
              "Register it with GraphQL::AnyCable.register_subscription_store(:#{adapter}) { ... }"
      end

      def inferred_subscription_store
        adapter = ::AnyCable.broadcast_adapter
        return :redis if defined?(::AnyCable::BroadcastAdapters::Redis) && adapter.is_a?(::AnyCable::BroadcastAdapters::Redis)

        :redis
      end

      def build_subscription_store(factory)
        return factory.call if factory.arity.zero?

        factory.call(config)
      end

      def subscription_store_registry
        @subscription_store_registry ||= {
          redis: lambda do
            SubscriptionStores::Redis.new(redis_connector: ->(&block) { with_redis(&block) }, config: config)
          end
        }
      end
    end
  end
end
