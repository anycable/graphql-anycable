# frozen_string_literal: true

module GraphQL
  module Anycable
    module Cleaner
      extend self

      def clean(subscription_expiration_seconds, use_redis_object_on_cleanup: true)
        clean_channels(subscription_expiration_seconds, use_redis_object_on_cleanup: use_redis_object_on_cleanup)
        clean_subscriptions(subscription_expiration_seconds, use_redis_object_on_cleanup: use_redis_object_on_cleanup)
        clean_events
      end

      def clean_channels(subscription_expiration_seconds, use_redis_object_on_cleanup: true)
        return unless subscription_expiration_seconds
        return unless use_redis_object_on_cleanup

        redis.scan_each(match: "#{adapter::CHANNEL_PREFIX}*") do |key|
          idle = redis.object("IDLETIME", key)
          next if idle&.<= subscription_expiration_seconds

          redis.del(key)
        end
      end

      def clean_subscriptions(subscription_expiration_seconds, use_redis_object_on_cleanup: true)
        return unless subscription_expiration_seconds
        return unless use_redis_object_on_cleanup

        redis.scan_each(match: "#{adapter::SUBSCRIPTION_PREFIX}*") do |key|
          idle = redis.object("IDLETIME", key)
          next if idle&.<= subscription_expiration_seconds

          redis.del(key)
        end
      end

      def clean_events
        redis.scan_each(match: "#{adapter::SUBSCRIPTION_EVENTS_PREFIX}*") do |key|
          subscription_id = key.sub(/\A#{adapter::SUBSCRIPTION_EVENTS_PREFIX}/, "")
          next if redis.exists(adapter::SUBSCRIPTION_PREFIX + subscription_id)

          redis.smembers(key).each do |event_topic|
            redis.srem(adapter::EVENT_PREFIX + event_topic, subscription_id)
          end

          redis.del(key)
        end
      end

      private

      def adapter
        GraphQL::Subscriptions::AnyCableSubscriptions
      end

      def redis
        GraphQL::Anycable.redis
      end
    end
  end
end
