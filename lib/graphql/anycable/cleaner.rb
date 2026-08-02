# frozen_string_literal: true

module GraphQL
  module AnyCable
    module Cleaner
      extend self

      def clean
        cleaner.clean
      end

      def clean_channels
        cleaner.clean_channels
      end

      def clean_subscriptions
        cleaner.clean_subscriptions
      end

      def clean_fingerprint_subscriptions
        cleaner.clean_fingerprint_subscriptions
      end

      def clean_topic_fingerprints
        cleaner.clean_topic_fingerprints
      end

      private

      def cleaner
        store = GraphQL::AnyCable.subscription_store
        return store.cleaner if store.respond_to?(:cleaner)

        raise "GraphQL::AnyCable subscription store #{store.class} does not support cleanup. " \
              "Implement #cleaner returning an object that responds to the cleanup methods."
      end
    end
  end
end
