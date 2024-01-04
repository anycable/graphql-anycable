# frozen_string_literal: true

require "timecop"

RSpec.describe GraphQL::AnyCable::Cleaner do
  let(:query) do
    <<~GRAPHQL
      subscription SomeSubscription { productUpdated { id } }
    GRAPHQL
  end

  let(:channel) do
    socket = double("Socket", istate: AnyCable::Socket::State.new({}))
    connection = double("Connection", anycable_socket: socket)
    double("Channel", id: "legacy_id", params: { "channelId" => "legacy_id" }, stream_from: nil, connection: connection)
  end

  let(:subscription_id) do
    "some-truly-random-number"
  end

  let(:redis) { GraphQL::AnyCable.redis }

  before do
    AnycableSchema.execute(
      query: query,
      context: { channel: channel, subscription_id: subscription_id },
      variables: {},
      operation_name: "SomeSubscription",
    )
  end

  describe ".clean_subscriptions" do
    context "when expired_seconds passed via argument" do
      context "when subscriptions are expired" do
        let(:lifetime_in_seconds) { 10 }

        it "cleans subscriptions" do
          expect(redis.keys("graphql-subscription:*").count).to be > 0

          Timecop.freeze(Time.now + 10) do
            described_class.clean_subscriptions(lifetime_in_seconds)
          end

          expect(redis.keys("graphql-subscription:*").count).to be 0
        end
      end

      context "when subscriptions are not expired" do
        let(:lifetime_in_seconds) { 100 }

        it "not cleans subscriptions" do
          described_class.clean_subscriptions(lifetime_in_seconds)

          expect(redis.keys("graphql-subscription:*").count).to be > 0
        end
      end
    end

    context "when expired_seconds passed via config" do
      context "when subscriptions are expired" do
        around do |ex|
          old_value = GraphQL::AnyCable.config.subscription_expiration_seconds
          GraphQL::AnyCable.config.subscription_expiration_seconds = 10

          ex.run

          GraphQL::AnyCable.config.subscription_expiration_seconds = old_value
        end

        it "cleans subscriptions" do
          expect(redis.keys("graphql-subscription:*").count).to be > 0

          Timecop.freeze(Time.now + 10) do
            described_class.clean_subscriptions
          end

          expect(redis.keys("graphql-subscription:*").count).to be 0
        end
      end

      context "when config.subscription_expiration_seconds is nil" do
        it "remains subscriptions" do
          Timecop.freeze(Time.now + 10) do
            described_class.clean_subscriptions
          end

          expect(redis.keys("graphql-subscription:*").count).to be > 0
        end
      end
    end

    context "when an expiration_seconds is not positive integer" do
      it "does not clean subscriptions" do
        expect(described_class).to_not receive(:remove_old_objects)

        described_class.clean_subscriptions("")

        expect(redis.keys("graphql-subscription:*").count).to be > 0
      end
    end
  end

  describe ".clean_channels" do
    context "when expired_seconds passed via argument" do
      context "when channels are expired" do
        let(:lifetime_in_seconds) { 10 }

        it "cleans subscriptions" do
          expect(redis.keys("graphql-channel:*").count).to be > 0

          Timecop.freeze(Time.now + 10) do
            described_class.clean_channels(lifetime_in_seconds)
          end

          expect(redis.keys("graphql-channel:*").count).to be 0
        end
      end

      context "when channels are not expired" do
        let(:lifetime_in_seconds) { 100 }

        it "does not clean channels" do
          described_class.clean_channels(lifetime_in_seconds)

          expect(redis.keys("graphql-channel:*").count).to be > 0
        end
      end
    end

    context "when an expiration_seconds is not positive integer" do
      it "does not clean channels" do
        expect(described_class).to_not receive(:remove_old_objects)

        described_class.clean_channels("")

        expect(redis.keys("graphql-channel:*").count).to be > 0
      end
    end
  end

  describe ".clean_fingerprint_subscriptions" do
    context "when subscription is blank" do
      subject do
        AnycableSchema.subscriptions.delete_subscription(subscription_id)

        described_class.clean_fingerprint_subscriptions
      end

      it "cleans graphql-subscriptions" do
        subscriptions_key = redis.keys("graphql-subscriptions:*")[0]

        expect(redis.smembers(subscriptions_key).empty?).to be false

        subject

        expect(redis.smembers(subscriptions_key).empty?).to be true
      end
    end
  end

  describe ".clean_topic_fingerprints" do
    subject do
      # Emulate situation, when subscriptions in fingerprints are orphan
      redis.scan_each(match: "graphql-subscriptions:*").each do |k|
        redis.del(k)
      end

      described_class.clean_topic_fingerprints
    end

    it "cleans fingerprints" do
      expect(redis.zrange("graphql-fingerprints::productUpdated:", 0, -1).empty?).to be false

      subject

      expect(redis.zrange("graphql-fingerprints::productUpdated:", 0, -1).empty?).to be true
    end
  end
end
