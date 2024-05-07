# frozen_string_literal: true

require "graphql"

require_relative "graphql/anycable/version"
require_relative "graphql/anycable/cleaner"
require_relative "graphql/anycable/config"
require_relative "graphql/anycable/railtie" if defined?(Rails)
require_relative "graphql/anycable/stats"
require_relative "graphql/anycable/delivery_adapter"
require_relative "graphql/subscriptions/anycable_subscriptions"

module GraphQL
  module AnyCable
    def self.use(schema, **options)
      schema.use GraphQL::Subscriptions::AnyCableSubscriptions, **options
    end

    def self.stats(**options)
      Stats.new(**options).collect
    end

    def self.delivery_method=(args)
      method_name, options = Array(args)
      options ||= {}

      config.delivery_method = method_name
      config.queue = options[:queue] if options[:queue]
      config.job_class = options[:job_class] if options[:job_class]
    end

    def self.delivery_adapter(object)
      DeliveryAdapter.lookup(executor_object: object)
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
