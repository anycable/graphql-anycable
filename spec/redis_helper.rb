# frozen_string_literal: true

def configure_test_redis_db
  url = ENV.fetch("REDIS_URL", "redis://localhost:6379/6") # AnyCable uses Redis DB number 5 by default
  channel = AnyCable.broadcast_adapter.channel
  AnyCable.broadcast_adapter = :redis, { url: url, channel: channel }
end

configure_test_redis_db

RSpec.configure do |config|
  config.before(:example) do
    GraphQL::AnyCable.redis.flushdb
  end
end
