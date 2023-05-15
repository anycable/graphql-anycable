# frozen_string_literal: true

module GraphQL
  module AnyCable
    module Cleaner
      extend self

      def clean
        clean_channels
        clean_subscriptions
        clean_fingerprint_subscriptions
        clean_topic_fingerprints
      end

      def clean_channels
        return unless config.subscription_expiration_seconds
        return unless config.use_redis_object_on_cleanup

        redis.scan_each(match: "#{adapter::CHANNEL_PREFIX}*") do |key|
          idle = redis.object("IDLETIME", key)
          next if idle&.<= config.subscription_expiration_seconds

          redis.del(key)
        end
      end

      def clean_subscriptions
        return unless config.subscription_expiration_seconds
        return unless config.use_redis_object_on_cleanup

        redis.scan_each(match: "#{adapter::SUBSCRIPTION_PREFIX}*") do |key|
          idle = redis.object("IDLETIME", key)
          next if idle&.<= config.subscription_expiration_seconds

          redis.del(key)
        end
      end

      def clean_fingerprint_subscriptions
        redis.scan_each(match: "#{adapter::SUBSCRIPTIONS_PREFIX}*") do |key|
          redis.smembers(key).each do |subscription_id|
            next if redis.exists?(adapter::SUBSCRIPTION_PREFIX + subscription_id)

            redis.srem(key, subscription_id)
          end
        end
      end

      def clean_topic_fingerprints
        redis.scan_each(match: "#{adapter::FINGERPRINTS_PREFIX}*") do |key|
          redis.zremrangebyscore(key, "-inf", "0")
          redis.zrange(key, 0, -1).each do |fingerprint|
            next if redis.exists?(adapter::SUBSCRIPTIONS_PREFIX + fingerprint)

            redis.zrem(key, fingerprint)
          end
        end
      end

      private

      def adapter
        GraphQL::Subscriptions::AnyCableSubscriptions
      end

      def redis
        GraphQL::AnyCable.redis
      end

      def config
        GraphQL::AnyCable.config
      end
    end
  end
end
