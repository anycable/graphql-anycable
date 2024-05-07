# frozen_string_literal: true

module GraphQL
  module Serializers
    class AnyCableSubscriptionSerializer < ActiveJob::Serializers::ObjectSerializer
      def serialize?(argument)
        argument.kind_of?(GraphQL::Subscriptions::AnyCableSubscriptions)
      end

      def serialize(subscription)
        super(subscription.collected_arguments)
      end

      def deserialize(payload)
        GraphQL::Subscriptions::AnyCableSubscriptions.new(**payload)
      end
    end
  end
end
