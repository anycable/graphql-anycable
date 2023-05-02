# frozen_string_literal: true

def configure_test_redis_db
  unless url = ENV.fetch("REDIS_URL", nil)
    conn = AnyCable.broadcast_adapter.redis_conn.connection
    channel = AnyCable.broadcast_adapter.channel
    new_db_index = conn[:db] + 1 # raises error if > number of redis databases
    url = "redis://#{conn[:host]}:#{conn[:port]}/#{new_db_index}"
  end

  AnyCable.broadcast_adapter = :redis, { url: url, channel: channel }
end

configure_test_redis_db

RSpec.configure do |config|
  config.before(:example) do
    GraphQL::AnyCable.redis.flushdb
  end
end
