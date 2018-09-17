# frozen_string_literal: true

namespace :graphql do
  namespace :anycable do
    task :clean_expired_subscriptions do
      config = Graphql::Anycable::Config.new
      unless config.subscription_expiration_seconds
        warn "GraphQL::Anycable: No expiration set for subscriptions!"
        next
      end

      redis = Anycable::PubSub.new.redis_conn
      klass = GraphQL::Subscriptions::AnyCableSubscriptions

      # 1. Clean up old channels
      redis.scan_each(match: "#{klass::CHANNEL_PREFIX}*") do |key|
        idle = redis.object("IDLETIME", key)
        next if idle&.<= config.subscription_expiration_seconds
        redis.del(key)
      end

      # 2. Clean up old subscriptions (they should have expired by themselves)
      redis.scan_each(match: "#{klass::SUBSCRIPTION_PREFIX}*") do |key|
        idle = redis.object("IDLETIME", key)
        next if idle&.<= config.subscription_expiration_seconds
        redis.del(key)
      end

      # 3. Clean up subscription_ids from events for expired subscriptions
      redis.scan_each(match: "#{klass::SUBSCRIPTION_EVENTS_PREFIX}*") do |key|
        subscription_id = key.sub(/\A#{klass::SUBSCRIPTION_EVENTS_PREFIX}/, "")
        next if redis.exists(klass::SUBSCRIPTION_PREFIX + subscription_id)
        redis.smembers(key).each do |event_topic|
          redis.srem(klass::EVENT_PREFIX + event_topic, subscription_id)
        end
        redis.del(key)
      end
    end
  end
end
