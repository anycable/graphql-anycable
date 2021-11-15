# frozen_string_literal: true

require "anyway"

module GraphQL
  module AnyCable
    class Config < Anyway::Config
      config_name :graphql_anycable
      env_prefix  :graphql_anycable

      attr_config subscription_expiration_seconds: nil
      attr_config use_redis_object_on_cleanup: true
      attr_config handle_legacy_subscriptions: false
      attr_config use_client_provided_uniq_id: true

      on_load do
        next unless use_client_provided_uniq_id?

        warn "[Deprecated] Using client provided channel uniq IDs could lead to unexpected behaviour, " \
             " please, set GraphQL::AnyCable.config.use_client_provided_uniq_id = false or GRAPHQL_ANYCABLE_USE_CLIENT_PROVIDED_UNIQ_ID=false, " \
             " and update the `#unsubscribed` callback code according to the latest docs."
      end
    end
  end
end
