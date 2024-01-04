# frozen_string_literal: true

require "rails"

module GraphQL
  module AnyCable
    class Railtie < ::Rails::Railtie
      initializer "graphql_anycable.load_trigger_job" do
        ActiveSupport.on_load(:active_job) do
          require "graphql/jobs/trigger_job"
          require "graphql/serializers/anycable_subscription_serializer"

          ActiveJob::Serializers.add_serializers(GraphQL::Serializers::AnyCableSubscriptionSerializer)
        end
      end

      rake_tasks do
        path = File.expand_path(__dir__)
        Dir.glob("#{path}/tasks/**/*.rake").each { |f| load f }
      end
    end
  end
end
