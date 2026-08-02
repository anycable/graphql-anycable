# frozen_string_literal: true

module GraphQL
  module AnyCable
    module SubscriptionStores
      class Redis
        class Stats
          def initialize(redis_connector:, config:, scan_count:, include_subscriptions:)
            @redis_connector = redis_connector
            @config = config
            @scan_count = scan_count
            @include_subscriptions = include_subscriptions
          end

          def collect
            result = {total: {}}

            with_redis do |redis|
              list_prefixes_keys.each do |name, prefix|
                result[:total][name] = count_by_scan(redis, match: "#{prefix}*", scan_count: scan_count)
              end

              if include_subscriptions
                result[:subscriptions] = group_subscription_stats(redis, scan_count: scan_count)
              end
            end

            result
          end

          private

          attr_reader :config, :redis_connector, :scan_count, :include_subscriptions

          def with_redis(&block)
            redis_connector.call(&block)
          end

          def redis_key(prefix)
            "#{config.redis_prefix}-#{prefix}"
          end

          def count_by_scan(redis, match:, scan_count:)
            total = 0
            cursor = "0"

            loop do
              cursor, keys = redis.scan(cursor, match: match, count: scan_count)
              total += keys.count

              break if cursor == "0"
            end

            total
          end

          def group_subscription_stats(redis, scan_count:)
            subscription_groups = {}

            redis.scan_each(match: "#{list_prefixes_keys[:fingerprints]}*", count: scan_count) do |fingerprint_key|
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

          def list_prefixes_keys
            {
              subscription: redis_key(SUBSCRIPTION_PREFIX),
              fingerprints: redis_key(FINGERPRINTS_PREFIX),
              subscriptions: redis_key(SUBSCRIPTIONS_PREFIX),
              channel: redis_key(CHANNEL_PREFIX)
            }
          end
        end
      end
    end
  end
end
