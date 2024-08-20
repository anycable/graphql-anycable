# frozen_string_literal: true

require "graphql-anycable"

namespace :graphql do
  namespace :anycable do
    desc "Clean up stale graphql channels and subscriptions from redis"
    task clean: %i[clean:channels clean:subscriptions clean:fingerprint_subscriptions clean:topic_fingerprints]

    namespace :clean do
      # Clean up old channels
      task :channels do
        GraphQL::AnyCable::Cleaner.clean_channels
      end

      # Clean up old subscriptions (they should have expired by themselves)
      task :subscriptions do
        GraphQL::AnyCable::Cleaner.clean_subscriptions
      end

      # Clean up subscription_ids from event fingerprints for expired subscriptions
      task :fingerprint_subscriptions do
        GraphQL::AnyCable::Cleaner.clean_fingerprint_subscriptions
      end

      # Clean up fingerprints from event topics. for expired subscriptions
      task :topic_fingerprints do
        GraphQL::AnyCable::Cleaner.clean_topic_fingerprints
      end
    end
  end
end
