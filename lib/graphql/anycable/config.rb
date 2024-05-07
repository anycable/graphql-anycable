# frozen_string_literal: true

require "anyway"

module GraphQL
  module AnyCable
    class Config < Anyway::Config
      config_name :graphql_anycable
      env_prefix  :graphql_anycable

      attr_config subscription_expiration_seconds: nil
      attr_config use_redis_object_on_cleanup: true
      attr_config redis_prefix: "graphql" # Here, we set clear redis_prefix without any hyphen. The hyphen is added at the end of this value on our side.

      attr_config delivery_method: "inline", queue: "default", job_class: "GraphQL::Jobs::TriggerJob"

      def job_class=(value)
        ensure_value_is_not_blank!("job_class", value)

        super
      end

      def queue=(value)
        ensure_value_is_not_blank!("queue", value)

        super
      end

      def delivery_method=(value)
        ensure_value_is_not_blank!("delivery_method", value)

        super
      end

      private

      def empty_value?(value)
        value.nil? || value == ""
      end

      def ensure_value_is_not_blank!(name, value)
        return unless empty_value?(value)

        raise_validation_error("#{name} can not be blank")
      end
    end
  end
end
