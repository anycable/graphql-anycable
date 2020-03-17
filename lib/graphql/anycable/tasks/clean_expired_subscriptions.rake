# frozen_string_literal: true

require "graphql-anycable"

namespace :graphql do
  namespace :anycable do
    desc "Clean up stale graphql channels, subscriptions, and events from redis"
    task clean: %i[clean:channels clean:subscriptions clean:events]

    # Old name that was used earlier
    task clean_expired_subscriptions: :clean

    namespace :clean do
      # Clean up old channels
      task :channels do
        GraphQL::Anycable::Cleaner.clean_channels
      end

      # Clean up old subscriptions (they should have expired by themselves)
      task :subscriptions do
        GraphQL::Anycable::Cleaner.clean_subscriptions
      end

      # Clean up subscription_ids from events for expired subscriptions
      task :events do
        GraphQL::Anycable::Cleaner.clean_events
      end
    end
  end
end
