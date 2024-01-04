# frozen_string_literal: true

require "graphql/adapters/base_adapter"
require "graphql/adapters/inline_adapter"
require "graphql/adapters/active_job_adapter"

module GraphQL
  module AnyCable
    class DeliveryAdapter
      class << self
        def lookup(options)
          adapter_class_name = config.delivery_method.to_s.split("_").map(&:capitalize).join

          Adapters.const_get("#{adapter_class_name}Adapter").new(**(options || {}))
        rescue NameError => e
          raise e.class, "Delivery adapter :#{config.delivery_method} haven't been found", e.backtrace
        end

        def config
          GraphQL::AnyCable.config
        end
      end
    end
  end
end
