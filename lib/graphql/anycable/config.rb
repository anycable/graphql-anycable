# frozen_string_literal: true

require "anyway"

module Graphql
  module Anycable
    class Config < Anyway::Config
      config_name :graphql_anycable
      env_prefix  :graphql_anycable

      attr_config subscription_expiration_seconds: nil
    end
  end
end
