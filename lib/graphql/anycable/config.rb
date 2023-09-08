# frozen_string_literal: true

require "anyway"

module GraphQL
  module AnyCable
    class Config < Anyway::Config
      config_name :graphql_anycable
      env_prefix  :graphql_anycable

      attr_config subscription_expiration_seconds: nil
      attr_config use_redis_object_on_cleanup: true
      attr_config use_client_provided_uniq_id: true
      attr_config redis_prefix: "graphql-"

      def redis_prefix
        Thread.current[:graphql_anycable_redis_prefix] || super
      end
    end
  end
end
