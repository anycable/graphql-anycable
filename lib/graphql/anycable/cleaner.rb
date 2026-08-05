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

        clean_idle_keys(adapter::CHANNEL_PREFIX)
      end

      def clean_subscriptions
        return unless config.subscription_expiration_seconds
        return unless config.use_redis_object_on_cleanup

        clean_idle_keys(adapter::SUBSCRIPTION_PREFIX)
      end

      def clean_fingerprint_subscriptions
        AnyCable.with_redis do |redis|
          each_key(redis, adapter::SUBSCRIPTIONS_PREFIX) do |key|
            each_batch(redis.sscan_each(key, count: redis_scan_count)) do |subscription_ids|
              stale = missing_key_ids(redis, adapter::SUBSCRIPTION_PREFIX, subscription_ids)
              redis.srem(key, stale) unless stale.empty?
            end
          end
        end
      end

      def clean_topic_fingerprints
        AnyCable.with_redis do |redis|
          each_key(redis, adapter::FINGERPRINTS_PREFIX) do |key|
            redis.zremrangebyscore(key, "-inf", "0")

            each_batch(redis.zscan_each(key, count: redis_scan_count)) do |members|
              fingerprints = members.map(&:first)
              stale = missing_key_ids(redis, adapter::SUBSCRIPTIONS_PREFIX, fingerprints)
              redis.zrem(key, stale) unless stale.empty?
            end
          end
        end
      end

      private

      def clean_idle_keys(prefix)
        AnyCable.with_redis do |redis|
          each_batch(redis.scan_each(match: "#{redis_key(prefix)}*", count: redis_scan_count)) do |keys|
            idle_times = redis.pipelined do |pipeline|
              keys.each { |key| pipeline.object("IDLETIME", key) }
            end

            expired = keys.reject.with_index { |_key, index| idle_times[index]&.<= config.subscription_expiration_seconds }
            redis.del(*expired) unless expired.empty?
          end
        end
      end

      # Iterates over the keys matching the given prefix, one key at a time.
      def each_key(redis, prefix, &block)
        redis.scan_each(match: "#{redis_key(prefix)}*", count: redis_scan_count, &block)
      end

      # Consumes a lazy enumerator (SCAN family) in batches to keep memory usage bounded.
      def each_batch(enumerator, &block)
        enumerator.each_slice(redis_scan_count, &block)
      end

      # Returns the ids which have no corresponding key in redis anymore, checking them in a single round trip.
      def missing_key_ids(redis, prefix, ids)
        exists = redis.pipelined do |pipeline|
          ids.each { |id| pipeline.exists?(redis_key(prefix) + id) }
        end

        # Reject ids that has corresponding key in Redis in `exists` array of pipelined responses.
        ids.reject.with_index { |_id, index| exists[index] }
      end

      def adapter
        GraphQL::Subscriptions::AnyCableSubscriptions
      end

      def config
        GraphQL::AnyCable.config
      end

      def redis_scan_count
        config.redis_scan_count.to_i
      end

      def redis_key(prefix)
        "#{config.redis_prefix}-#{prefix}"
      end
    end
  end
end
