# frozen_string_literal: true

module GraphQL
  module AnyCable
    # Calculates  amount of Graphql Redis keys
    # (graphql-subscription, graphql-fingerprints, graphql-subscriptions, graphql-channel)
    # Also, calculate the number of subscribers grouped by subscriptions
    class Stats
      SCAN_COUNT_RECORDS_AMOUNT = 1_000

      attr_reader :redis, :config, :list_prefixes_keys, :include_subscriptions

      def initialize(redis:, config:, include_subscriptions: false)
        @redis = redis
        @config = config
        @include_subscriptions = include_subscriptions
        @list_prefix_keys = list_prefixes_keys
      end

      def collect
        total_subscriptions_result = {total: {}}

        list_prefixes_keys.each do |name, prefix|
          total_subscriptions_result[:total][name] = count_by_scan(match: "#{prefix}*")
        end

        if include_subscriptions
          total_subscriptions_result[:subscriptions] = group_subscription_stats
        end

        total_subscriptions_result
      end

      private

      # Counting all keys, that match the pattern with iterating by count
      def count_by_scan(match:, count: SCAN_COUNT_RECORDS_AMOUNT)
        sb_amount = 0
        cursor = '0'

        loop do
          cursor, result = redis.scan(cursor, match: match, count: count)
          sb_amount += result.count

          break if cursor == '0'
        end

        sb_amount
      end

      # Calculate subscribes, grouped by subscriptions
      def group_subscription_stats
        subscription_groups = {}
        redis.scan_each(match: "#{list_prefixes_keys[:fingerprints]}*", count: SCAN_COUNT_RECORDS_AMOUNT) do |fingerprint_key|
          subscription_name = fingerprint_key.gsub(/#{list_prefixes_keys[:fingerprints]}|:/, "")
          subscription_groups[subscription_name] = 0

          redis.zscan_each(fingerprint_key) do |data|
            redis.sscan_each("#{list_prefixes_keys[:subscriptions]}#{data[0]}") do |subscription_key|
              next unless redis.exists?("#{list_prefixes_keys[:subscription]}#{subscription_key}")

              subscription_groups[subscription_name] += 1
            end
          end
        end

        subscription_groups
      end

      def adapter
        GraphQL::Subscriptions::AnyCableSubscriptions
      end

      def list_prefixes_keys
        {
          subscription: redis_key(adapter::SUBSCRIPTION_PREFIX),
          fingerprints: redis_key(adapter::FINGERPRINTS_PREFIX),
          subscriptions: redis_key(adapter::SUBSCRIPTIONS_PREFIX),
          channel: redis_key(adapter::CHANNEL_PREFIX)
        }
      end

      def redis_key(prefix)
        "#{config.redis_prefix}-#{prefix}"
      end
    end
  end
end
