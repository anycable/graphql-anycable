# frozen_string_literal: true

module GraphQL
  module Jobs
    class TriggerJob < ActiveJob::Base
      def perform(executor_object, execute_method, event_name, args = {}, object = nil, options = {})
        executor_object.public_send(execute_method, event_name, args, object, **options)
      end
    end
  end
end
