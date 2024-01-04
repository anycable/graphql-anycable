# frozen_string_literal: true

module GraphQL
  module Adapters
    class ActiveJobAdapter < BaseAdapter
      def trigger(...)
        executor_class_job.set(queue: config.queue).perform_later(
          executor_object,
          executor_method,
          ...
        )
      end

      private

      def executor_class_job
        config.job_class.constantize
      end

      def config
        GraphQL::AnyCable.config
      end
    end
  end
end
