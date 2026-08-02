# frozen_string_literal: true

module GraphQL
  module AnyCable
    # Collects subscription store statistics through the configured backend.
    class Stats
      SCAN_COUNT_RECORDS_AMOUNT = 1_000

      attr_reader :scan_count, :include_subscriptions

      def initialize(scan_count: SCAN_COUNT_RECORDS_AMOUNT, include_subscriptions: false)
        @scan_count = scan_count
        @include_subscriptions = include_subscriptions
      end

      def collect
        AnyCable.subscription_store.stats(scan_count: scan_count, include_subscriptions: include_subscriptions)
      end
    end
  end
end
