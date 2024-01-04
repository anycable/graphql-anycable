# frozen_string_literal: true

module GraphQL
  module Adapters
    class InlineAdapter < BaseAdapter
      def trigger(...)
        executor_object.public_send(executor_method, ...)
      end
    end
  end
end
