# frozen_string_literal: true

require "graphql"

require_relative "graphql/anycable/version"
require_relative "graphql/anycable/cleaner"
require_relative "graphql/anycable/config"
require_relative "graphql/anycable/railtie" if defined?(Rails)
require_relative "graphql/subscriptions/anycable_subscriptions"

module GraphQL
  module AnyCable
    def self.use(schema, **options)
      if config.use_client_provided_uniq_id?
        warn "[Deprecated] Using client provided channel uniq IDs could lead to unexpected behaviour, " \
             "please, set GraphQL::AnyCable.config.use_client_provided_uniq_id = false or GRAPHQL_ANYCABLE_USE_CLIENT_PROVIDED_UNIQ_ID=false, " \
             "and update the `#unsubscribed` callback code according to the latest docs."
      end

      schema.use GraphQL::Subscriptions::AnyCableSubscriptions, **options
    end

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

    def config
      @config ||= GraphQL::AnyCable::Config.new
    end

    def configure
      yield(config) if block_given?
    end
  end
end
