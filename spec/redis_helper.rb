# frozen_string_literal: true

REDIS_TEST_DB_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379/6")

channel = AnyCable.broadcast_adapter.channel

AnyCable.broadcast_adapter = :redis, {url: REDIS_TEST_DB_URL, channel: channel}

$redis = Redis.new(url: REDIS_TEST_DB_URL)

RSpec.configure do |config|
  config.before do
    GraphQL::AnyCable.with_redis { _1.flushdb }
  end
end
