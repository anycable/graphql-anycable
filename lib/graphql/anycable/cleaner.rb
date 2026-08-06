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
          each_key_batch(redis, adapter::SUBSCRIPTIONS_PREFIX) do |keys|
            bulk_readable, oversized = partition_by_size(redis, keys, :scard)

            each_capped_chunk(bulk_readable) do |chunk|
              members = redis.pipelined { |pipeline| chunk.each { |key| pipeline.smembers(key) } }
              remove_stale(redis, adapter::SUBSCRIPTION_PREFIX, chunk.zip(members), :srem)
            end

            oversized.each do |key|
              each_batch(redis.sscan_each(key, count: redis_scan_count)) do |subscription_ids|
                remove_stale(redis, adapter::SUBSCRIPTION_PREFIX, [[key, subscription_ids]], :srem)
              end
            end
          end
        end
      end

      def clean_topic_fingerprints
        AnyCable.with_redis do |redis|
          each_key_batch(redis, adapter::FINGERPRINTS_PREFIX) do |keys|
            redis.pipelined { |pipeline| keys.each { |key| pipeline.zremrangebyscore(key, "-inf", "0") } }

            bulk_readable, oversized = partition_by_size(redis, keys, :zcard)

            each_capped_chunk(bulk_readable) do |chunk|
              fingerprints = redis.pipelined { |pipeline| chunk.each { |key| pipeline.zrange(key, 0, -1) } }
              remove_stale(redis, adapter::SUBSCRIPTIONS_PREFIX, chunk.zip(fingerprints), :zrem)
            end

            oversized.each do |key|
              each_batch(redis.zscan_each(key, count: redis_scan_count)) do |members|
                remove_stale(redis, adapter::SUBSCRIPTIONS_PREFIX, [[key, members.map(&:first)]], :zrem)
              end
            end
          end
        end
      end

      private

      def clean_idle_keys(prefix)
        AnyCable.with_redis do |redis|
          each_key_batch(redis, prefix) do |keys|
            idle_times = redis.pipelined do |pipeline|
              keys.each { |key| pipeline.object("IDLETIME", key) }
            end

            expired = keys.reject.with_index { |_key, index| idle_times[index]&.<= config.subscription_expiration_seconds }
            redis.del(*expired) unless expired.empty?
          end
        end
      end

      # Splits keys into those small enough to read in one go and those that have to be iterated
      # with a cursor. Most collections hold only a handful of members, and reading many of them
      # per round trip is what keeps cleanup bearable when there are a lot of keys; the rare huge
      # ones still have to be iterated, or they would blow up memory in the process.
      def partition_by_size(redis, keys, size_command)
        sizes = redis.pipelined do |pipeline|
          keys.each { |key| pipeline.public_send(size_command, key) }
        end

        bulk_readable, oversized = keys.zip(sizes).partition { |_key, size| size <= redis_scan_count }
        [bulk_readable, oversized.map(&:first)]
      end

      # Yields key chunks whose combined size stays within redis_scan_count.
      def each_capped_chunk(sized_keys)
        chunk, total = [], 0

        sized_keys.each do |key, size|
          if chunk.any? && total + size > redis_scan_count
            yield chunk
            chunk, total = [], 0
          end

          chunk << key
          total += size
        end

        yield chunk if chunk.any?
      end

      # Removes the members which no longer have a corresponding key in redis, given `[key, members]`
      # pairs for one or more collections. Takes two round trips for the whole lot, however many
      # collections and members it is handed: one for the existence checks and one for the removals.
      def remove_stale(redis, prefix, members_by_key, remove_command)
        pairs = members_by_key.flat_map { |key, members| members.map { |member| [key, member] } }
        return if pairs.empty?

        stale = missing_key_pairs(redis, prefix, pairs)
        return if stale.empty?

        redis.pipelined do |pipeline|
          stale.group_by(&:first).each do |key, key_pairs|
            pipeline.public_send(remove_command, key, key_pairs.map(&:last))
          end
        end
      end

      # Iterates over the keys matching the given prefix in batches, to allow pipelining.
      def each_key_batch(redis, prefix, &block)
        each_batch(redis.scan_each(match: "#{redis_key(prefix)}*", count: redis_scan_count), &block)
      end

      # Consumes a lazy enumerator (SCAN family) in batches to keep memory usage bounded.
      def each_batch(enumerator, &block)
        enumerator.each_slice(redis_scan_count, &block)
      end

      # Returns the `[key, member]` pairs whose member has no corresponding key in redis anymore,
      # checking all of them in a single round trip. The member cannot be looked up on its own,
      # since the same member may well appear in more than one collection.
      def missing_key_pairs(redis, prefix, pairs)
        exists = redis.pipelined do |pipeline|
          pairs.each { |_key, member| pipeline.exists?(redis_key(prefix) + member) }
        end

        # Reject pairs whose member has a corresponding key in Redis in `exists` array of pipelined responses.
        pairs.reject.with_index { |_pair, index| exists[index] }
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
