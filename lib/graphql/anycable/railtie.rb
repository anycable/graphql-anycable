# frozen_string_literal: true

require "rails"

module GraphQL
  module AnyCable
    class Railtie < ::Rails::Railtie
      rake_tasks do
        path = File.expand_path(__dir__)
        Dir.glob("#{path}/tasks/**/*.rake").each { |f| load f }
      end
    end
  end
end
