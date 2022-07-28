# frozen_string_literal: true

require "rails"

module GraphQL
  module AnyCable
    class Railtie < ::Rails::Railtie
      rake_tasks do
        path = File.expand_path(__dir__)
        Dir.glob("#{path}/tasks/**/*.rake").each { |f| load f }
      end

      config.after_initialize do
        if GraphQL::AnyCable.config.use_client_provided_uniq_id?
          warn "[Deprecated] Using client provided channel uniq IDs could lead to unexpected behaviour, " \
               "please, set GraphQL::AnyCable.config.use_client_provided_uniq_id = false or GRAPHQL_ANYCABLE_USE_CLIENT_PROVIDED_UNIQ_ID=false, " \
               "and update the `#unsubscribed` callback code according to the latest docs."
        end
      end
    end
  end
end
