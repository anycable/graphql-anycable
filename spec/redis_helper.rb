# frozen_string_literal: true

REDIS_TEST_DB_URL = "redis://localhost:6379/6"

def setup_redis_test_db
  test_url = ENV.fetch("REDIS_URL", REDIS_TEST_DB_URL)
  channel = AnyCable.broadcast_adapter.channel
  AnyCable.broadcast_adapter = :redis, { url: test_url, channel: channel }
end

setup_redis_test_db

RSpec.configure do |config|
  config.before do
    GraphQL::AnyCable.redis.flushdb
  end
end
