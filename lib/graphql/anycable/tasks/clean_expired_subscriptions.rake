require "graphql-anycable"

# frozen_string_literal: true

namespace :graphql do
  namespace :anycable do
    desc "Clean up stale graphql channels, subscriptions, and events from redis"
    task clean: %i[clean:channels clean:subscriptions clean:events]

    # Old name that was used earlier
    task clean_expired_subscriptions: :clean

    namespace :clean do
      KLASS = GraphQL::Subscriptions::AnyCableSubscriptions

      # Clean up old channels
      task :channels do
        next unless config.subscription_expiration_seconds
        next unless config.use_redis_object_on_cleanup

        redis.scan_each(match: "#{KLASS::CHANNEL_PREFIX}*") do |key|
          idle = redis.object("IDLETIME", key)
          next if idle&.<= config.subscription_expiration_seconds

          redis.del(key)
        end
      end

      # Clean up old subscriptions (they should have expired by themselves)
      task :subscriptions do
        next unless config.subscription_expiration_seconds
        next unless config.use_redis_object_on_cleanup

        redis.scan_each(match: "#{KLASS::SUBSCRIPTION_PREFIX}*") do |key|
          idle = redis.object("IDLETIME", key)
          next if idle&.<= config.subscription_expiration_seconds

          redis.del(key)
        end
      end

      # Clean up subscription_ids from events for expired subscriptions
      task :events do
        redis.scan_each(match: "#{KLASS::SUBSCRIPTION_EVENTS_PREFIX}*") do |key|
          subscription_id = key.sub(/\A#{KLASS::SUBSCRIPTION_EVENTS_PREFIX}/, "")
          next if redis.exists(KLASS::SUBSCRIPTION_PREFIX + subscription_id)

          redis.smembers(key).each do |event_topic|
            redis.srem(KLASS::EVENT_PREFIX + event_topic, subscription_id)
          end
          redis.del(key)
        end
      end
    end

    def config
      @config ||= GraphQL::Anycable::Config.new
    end

    def redis
      GraphQL::Anycable.redis
    end
  end
end
