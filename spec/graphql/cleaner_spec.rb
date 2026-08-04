# frozen_string_literal: true

RSpec.describe GraphQL::AnyCable::Cleaner do
  let(:config) { GraphQL::AnyCable.config }

  around do |example|
    old_scan_count = config.redis_scan_count
    old_expiration = config.subscription_expiration_seconds
    example.run
    config.redis_scan_count = old_scan_count
    config.subscription_expiration_seconds = old_expiration
  end

  # Enforce several SCAN/pipeline batches to make sure batching doesn't lose or skip anything.
  before { config.redis_scan_count = 2 }

  describe "#clean_fingerprint_subscriptions" do
    before do
      $redis.sadd("graphql-subscriptions:fingerprint-1", %w[alive-1 stale-1 stale-2 alive-2 stale-3])
      $redis.sadd("graphql-subscriptions:fingerprint-2", %w[stale-4])
      $redis.mapped_hmset("graphql-subscription:alive-1", {query: "{}"})
      $redis.mapped_hmset("graphql-subscription:alive-2", {query: "{}"})
    end

    it "removes subscription ids without a subscription hash" do
      described_class.clean_fingerprint_subscriptions

      expect($redis.smembers("graphql-subscriptions:fingerprint-1")).to contain_exactly("alive-1", "alive-2")
      expect($redis.exists?("graphql-subscriptions:fingerprint-2")).to be false
    end
  end

  describe "#clean_topic_fingerprints" do
    before do
      $redis.zadd("graphql-fingerprints:product-updated", [
        [1, "alive-1"], [1, "stale-1"], [0, "zero-scored"], [2, "stale-2"], [3, "alive-2"], [1, "stale-3"]
      ])
      $redis.sadd("graphql-subscriptions:alive-1", %w[sid-1])
      $redis.sadd("graphql-subscriptions:alive-2", %w[sid-2])
      $redis.sadd("graphql-subscriptions:zero-scored", %w[sid-3])
    end

    it "removes fingerprints without subscriptions and with non-positive scores" do
      described_class.clean_topic_fingerprints

      expect($redis.zrange("graphql-fingerprints:product-updated", 0, -1)).to contain_exactly("alive-1", "alive-2")
    end
  end

  describe "#clean_subscriptions" do
    before do
      $redis.mapped_hmset("graphql-subscription:sid-1", {query: "{}"})
      $redis.mapped_hmset("graphql-subscription:sid-2", {query: "{}"})
      $redis.mapped_hmset("graphql-subscription:sid-3", {query: "{}"})
    end

    it "keeps keys which are not idle for long enough" do
      config.subscription_expiration_seconds = 3600
      described_class.clean_subscriptions

      expect($redis.keys("graphql-subscription:*").size).to eq(3)
    end

    it "removes keys which are idle for longer than the expiration" do
      config.subscription_expiration_seconds = -1
      described_class.clean_subscriptions

      expect($redis.keys("graphql-subscription:*")).to be_empty
    end

    it "does nothing without expiration configured" do
      config.subscription_expiration_seconds = nil
      described_class.clean_subscriptions

      expect($redis.keys("graphql-subscription:*").size).to eq(3)
    end
  end

  describe "#clean_channels" do
    before do
      $redis.sadd("graphql-channel:sid-1", %w[sid-1])
      $redis.sadd("graphql-channel:sid-2", %w[sid-2])
      $redis.sadd("graphql-channel:sid-3", %w[sid-3])
    end

    it "removes keys which are idle for longer than the expiration" do
      config.subscription_expiration_seconds = -1
      described_class.clean_channels

      expect($redis.keys("graphql-channel:*")).to be_empty
    end
  end

  describe "redis round trips" do
    before do
      config.redis_scan_count = 1000
      $redis.sadd("graphql-subscriptions:fingerprint-1", (1..100).map { |i| "stale-#{i}" })
    end

    it "checks and removes members in batches instead of one by one" do
      commands = count_commands { described_class.clean_fingerprint_subscriptions }

      expect(commands["srem"]).to eq(1)
      expect(commands["smembers"]).to be_nil
    end

    # Counts the commands issued to redis using a MONITOR-like counter based on `INFO commandstats`.
    def count_commands
      before = command_stats
      yield
      command_stats.to_h { |command, calls| [command, calls - before.fetch(command, 0)] }
        .reject { |_command, calls| calls.zero? }
    end

    def command_stats
      $redis.info("commandstats").to_h do |command, stats|
        # Older redis-rb versions return the raw "calls=1,usec=..." string instead of a parsed hash.
        calls = stats.is_a?(Hash) ? stats["calls"] : stats[/calls=(\d+)/, 1]
        [command.delete_prefix("cmdstat_"), calls.to_i]
      end
    end
  end
end
