# frozen_string_literal: true

module GraphQL
  module AnyCable
    module SubscriptionStores
      class Redis
        class Cleaner
          def initialize(redis_connector:, config:)
            @redis_connector = redis_connector
            @config = config
          end

          def clean
            clean_channels
            clean_subscriptions
            clean_fingerprint_subscriptions
            clean_topic_fingerprints
          end

          def clean_channels
            return unless config.subscription_expiration_seconds
            return unless config.use_redis_object_on_cleanup

            with_redis do |redis|
              redis.scan_each(match: "#{redis_key(CHANNEL_PREFIX)}*") do |key|
                idle = redis.object("IDLETIME", key)
                next if idle&.<= config.subscription_expiration_seconds

                redis.del(key)
              end
            end
          end

          def clean_subscriptions
            return unless config.subscription_expiration_seconds
            return unless config.use_redis_object_on_cleanup

            with_redis do |redis|
              redis.scan_each(match: "#{redis_key(SUBSCRIPTION_PREFIX)}*") do |key|
                idle = redis.object("IDLETIME", key)
                next if idle&.<= config.subscription_expiration_seconds

                redis.del(key)
              end
            end
          end

          def clean_fingerprint_subscriptions
            with_redis do |redis|
              redis.scan_each(match: "#{redis_key(SUBSCRIPTIONS_PREFIX)}*") do |key|
                redis.smembers(key).each do |subscription_id|
                  next if redis.exists?(redis_key(SUBSCRIPTION_PREFIX) + subscription_id)

                  redis.srem(key, subscription_id)
                end
              end
            end
          end

          def clean_topic_fingerprints
            with_redis do |redis|
              redis.scan_each(match: "#{redis_key(FINGERPRINTS_PREFIX)}*") do |key|
                redis.zremrangebyscore(key, "-inf", "0")
                redis.zrange(key, 0, -1).each do |fingerprint|
                  next if redis.exists?(redis_key(SUBSCRIPTIONS_PREFIX) + fingerprint)

                  redis.zrem(key, fingerprint)
                end
              end
            end
          end

          private

          attr_reader :config, :redis_connector

          def with_redis(&block)
            redis_connector.call(&block)
          end

          def redis_key(prefix)
            "#{config.redis_prefix}-#{prefix}"
          end
        end
      end
    end
  end
end
