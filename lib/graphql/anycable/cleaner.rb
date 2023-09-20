# frozen_string_literal: true

module GraphQL
  module AnyCable
    module Cleaner
      extend self

      MAX_RECORDS_AT_ONCE = 1_000

      def clean
        clean_channels
        clean_subscriptions
        clean_fingerprint_subscriptions
        clean_topic_fingerprints
      end

      def clean_channels(expiration_seconds = nil)
        expiration_seconds ||= config.subscription_expiration_seconds

        return if expiration_seconds.nil? || expiration_seconds.to_i.zero?
        return unless config.use_redis_object_on_cleanup

        store_name = redis_key(adapter::CHANNELS_STORAGE_TIME)

        remove_old_objects(store_name, expiration_seconds.to_i)
      end

      def clean_subscriptions(expiration_seconds = nil)
        expiration_seconds ||= config.subscription_expiration_seconds

        return if expiration_seconds.nil? || expiration_seconds.to_i.zero?
        return unless config.use_redis_object_on_cleanup

        store_name = redis_key(adapter::SUBSCRIPTIONS_STORAGE_TIME)

        remove_old_objects(store_name, expiration_seconds.to_i)
      end

      # For cases, when we need to clear only `subscription time storage`
      def clean_subscription_time_storage
        clean_created_time_storage(redis_key(adapter::SUBSCRIPTIONS_STORAGE_TIME))
      end

      # For cases, when we need to clear only `channel time storage`
      def clean_channel_time_storage
        clean_created_time_storage(redis_key(adapter::CHANNELS_STORAGE_TIME))
      end

      def clean_fingerprint_subscriptions
        redis.scan_each(match: "#{redis_key(adapter::SUBSCRIPTIONS_PREFIX)}*") do |key|
          redis.smembers(key).each do |subscription_id|
            next if redis.exists?(redis_key(adapter::SUBSCRIPTION_PREFIX) + subscription_id)

            redis.srem(key, subscription_id)
          end
        end
      end

      def clean_topic_fingerprints
        redis.scan_each(match: "#{redis_key(adapter::FINGERPRINTS_PREFIX)}*") do |key|
          redis.zremrangebyscore(key, '-inf', '0')
          redis.zrange(key, 0, -1).each do |fingerprint|
            next if redis.exists?(redis_key(adapter::SUBSCRIPTIONS_PREFIX) + fingerprint)

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

      def redis_key(prefix)
        "#{config.redis_prefix}-#{prefix}"
      end

      def remove_old_objects(store_name, expiration_seconds)
        # Determine the time point before which the keys should be deleted
        time_point = (Time.now - expiration_seconds).to_i

        # iterating per 1000 records
        loop do
          # fetches keys, which need to be deleted
          keys = redis.zrangebyscore(store_name, "-inf", time_point, limit: [0, MAX_RECORDS_AT_ONCE])

          break if keys.empty?

          redis.multi do |pipeline|
            pipeline.del(*keys)
            pipeline.zrem(store_name, keys)
          end
        end
      end

      # For cases, when the key was dropped, but it remains in the `subscription/channel time storage`
      def clean_created_time_storage(storage_name)
        redis.zscan_each(storage_name, count: MAX_RECORDS_AT_ONCE) do |key|
          next if redis.exists?(key)

          redis.zrem(storage_name, key)
        end
      end
    end
  end
end
