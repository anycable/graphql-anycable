# frozen_string_literal: true

module GraphQL
  module Adapters
    class BaseAdapter
      attr_reader :executor_object, :executor_method

      def initialize(executor_object:)
        @executor_object = executor_object
        @executor_method = executor_object.class::EXECUTOR_METHOD_NAME
      end

      def trigger
        raise NoMethodError, "#{__method__} method should be implemented in concrete class"
      end
    end
  end
end
