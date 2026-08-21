# frozen_string_literal: true

RSpec.describe GraphQL::AnyCable do
  subject do
    AnycableSchema.execute(
      query: query,
      context: {channel: channel, subscription_id: subscription_id},
      variables: {},
      operation_name: "SomeSubscription"
    ).tap do |result|
      expect(result.to_h.fetch("errors", [])).to be_empty
    end
  end

  let(:query) do
    <<~GRAPHQL
      subscription SomeSubscription { productUpdated { id } }
    GRAPHQL
  end

  let(:expected_result) do
    <<~JSON.strip
      {"result":{"data":{"productUpdated":{"id":"1"}}},"more":true}
    JSON
  end

  let(:channel) do
    socket = double("Socket", istate: AnyCable::Socket::State.new({}))
    connection = double("Connection", anycable_socket: socket)
    double("Channel", __istate__: socket.istate, id: "legacy_id", params: {"channelId" => "legacy_id"}, stream_from: nil, connection: connection)
  end

  let(:subscription_id) do
    "some-truly-random-number"
  end

  let(:fingerprint) do
    ":productUpdated:/SomeSubscription/fBDZmJU1UGTorQWvOyUeaHVwUxJ3T9SEqnetj6SKGXc=/0/RBNvo1WzZ4oRRq0W9-hknpT7T8If536DEMBg9hyq_4o="
  end

  before do
    allow(AnyCable).to receive(:broadcast)
    allow_any_instance_of(GraphQL::Subscriptions::Event).to receive(:fingerprint).and_return(fingerprint)
    allow_any_instance_of(GraphQL::Subscriptions).to receive(:build_id).and_return("ohmycables")
  end

  it "subscribes channel to stream updates from GraphQL subscription" do
    subject
    expect(channel).to have_received(:stream_from).with("graphql-subscriptions:#{fingerprint}")
  end

  it "broadcasts message when event is being triggered" do
    subject
    AnycableSchema.subscriptions.trigger(:product_updated, {}, {id: 1, title: "foo"})
    expect(AnyCable).to have_received(:broadcast).with("graphql-subscriptions:#{fingerprint}", expected_result)
  end

  context "triggering update event" do
    let(:query) do
      <<~GRAPHQL
        subscription SomeSubscription {
          productUpdated { id }
        }
      GRAPHQL
    end

    it "broadcasts message only for update event" do
      subject
      AnycableSchema.subscriptions.trigger(:product_updated, {}, {id: 1, title: "foo"})
      expect(AnyCable).to have_received(:broadcast).with("graphql-subscriptions:#{fingerprint}", expected_result)
    end
  end

  context "triggering create event" do
    let(:query) do
      <<~GRAPHQL
        subscription SomeSubscription {
          productCreated { id title }
        }
      GRAPHQL
    end

    let(:expected_result) do
      <<~JSON.strip
        {"result":{"data":{"productCreated":{"id":"1","title":"Gravizapa"}}},"more":true}
      JSON
    end

    it "broadcasts message only for create event" do
      subject
      AnycableSchema.subscriptions.trigger(:product_created, {}, {id: 1, title: "Gravizapa"})

      expect(AnyCable).to have_received(:broadcast).with("graphql-subscriptions:#{fingerprint}", expected_result)
    end
  end

  context "with empty operation name" do
    subject do
      AnycableSchema.execute(
        query: query,
        context: {channel: channel, subscription_id: subscription_id},
        variables: {},
        operation_name: nil
      )
    end

    let(:query) do
      <<~GRAPHQL
        subscription { productUpdated { id } }
      GRAPHQL
    end

    it "subscribes channel to stream updates from GraphQL subscription" do
      subject
      expect(channel).to have_received(:stream_from).with("graphql-subscriptions:#{fingerprint}")
    end
  end

  describe ".delete_channel_subscriptions" do
    context "with default config.redis-prefix" do
      before do
        AnycableSchema.execute(
          query: query,
          context: {channel: channel, subscription_id: subscription_id},
          variables: {},
          operation_name: "SomeSubscription"
        )
      end

      let(:redis) { $redis }

      subject do
        AnycableSchema.subscriptions.delete_channel_subscriptions(channel)
      end

      it "removes subscription from redis" do
        expect(redis.exists?("graphql-subscription:some-truly-random-number")).to be true
        expect(redis.exists?("graphql-channel:some-truly-random-number")).to be true
        expect(redis.exists?("graphql-fingerprints::productUpdated:")).to be true
        subject
        expect(redis.exists?("graphql-channel:some-truly-random-number")).to be false
        expect(redis.exists?("graphql-fingerprints::productUpdated:")).to be false
        expect(redis.exists?("graphql-subscription:some-truly-random-number")).to be false
      end
    end

    context "when the channel carries several subscriptions" do
      let(:redis) { $redis }

      before do
        %w[sid-first sid-second].each do |sid|
          AnycableSchema.execute(
            query: query,
            context: {channel: channel, subscription_id: sid},
            variables: {},
            operation_name: "SomeSubscription"
          )
        end
      end

      it "removes all of them, not only the last one" do
        expect(redis.exists?("graphql-subscription:sid-first")).to be true
        expect(redis.exists?("graphql-subscription:sid-second")).to be true

        AnycableSchema.subscriptions.delete_channel_subscriptions(channel)

        aggregate_failures do
          expect(redis.exists?("graphql-subscription:sid-first")).to be false
          expect(redis.exists?("graphql-subscription:sid-second")).to be false
          expect(redis.keys("graphql-channel:*")).to be_empty
          expect(redis.keys("graphql-subscriptions:*")).to be_empty
          expect(redis.keys("graphql-fingerprints:*")).to be_empty
        end
      end
    end

    context "with different config.redis-prefix" do
      around do |ex|
        old_redis_prefix = GraphQL::AnyCable.config.redis_prefix
        GraphQL::AnyCable.config.redis_prefix = "graphql-test"

        ex.run

        GraphQL::AnyCable.config.redis_prefix = old_redis_prefix
      end

      before do
        AnycableSchema.execute(
          query: query,
          context: {channel: channel, subscription_id: subscription_id},
          variables: {},
          operation_name: "SomeSubscription"
        )
      end

      let(:redis) { $redis }

      subject do
        AnycableSchema.subscriptions.delete_channel_subscriptions(channel)
      end

      it "removes subscription from redis" do
        expect(redis.exists?("graphql-test-subscription:some-truly-random-number")).to be true
        expect(redis.exists?("graphql-test-channel:some-truly-random-number")).to be true
        expect(redis.exists?("graphql-test-fingerprints::productUpdated:")).to be true
        subject
        expect(redis.exists?("graphql-test-channel:some-truly-random-number")).to be false
        expect(redis.exists?("graphql-test-fingerprints::productUpdated:")).to be false
        expect(redis.exists?("graphql-test-subscription:some-truly-random-number")).to be false
      end
    end
  end

  describe ".delete_subscription" do
    let(:redis) { $redis }

    before do
      AnycableSchema.execute(
        query: query,
        context: {channel: channel, subscription_id: subscription_id},
        variables: {},
        operation_name: "SomeSubscription"
      )
    end

    it "removes subscription from redis" do
      expect(redis.exists?("graphql-subscription:some-truly-random-number")).to be true

      AnycableSchema.subscriptions.delete_subscription(subscription_id)

      aggregate_failures do
        expect(redis.exists?("graphql-subscription:some-truly-random-number")).to be false
        expect(redis.keys("graphql-subscriptions:*")).to be_empty
        expect(redis.keys("graphql-fingerprints:*")).to be_empty
      end
    end

    # Bare +AnyCable+ resolves to +GraphQL::AnyCable+ inside the adapter, so the former
    # default checked a connection out of the pool and then kept using it forever.
    it "borrows a connection instead of the deprecated global one" do
      expect(GraphQL::AnyCable).not_to receive(:redis)

      AnycableSchema.subscriptions.delete_subscription(subscription_id)
    end
  end

  describe ".read_subscription" do
    let(:redis) { $redis }

    before do
      AnycableSchema.execute(
        query: query,
        context: {channel: channel, subscription_id: subscription_id},
        variables: {},
        operation_name: "SomeSubscription"
      )
      redis.del("graphql-subscription:#{subscription_id}")
    end

    it "raises when the subscription is no longer stored" do
      expect { AnycableSchema.subscriptions.read_subscription(subscription_id) }
        .to raise_error(GraphQL::AnyCable::SubscriptionExpiredError, subscription_id)
    end
  end

  describe "with missing channel instance in execution context" do
    subject do
      AnycableSchema.execute(
        query: query,
        context: {}, # Intentionally left blank
        variables: {},
        operation_name: "SomeSubscription"
      )
    end

    let(:query) do
      <<~GRAPHQL
        subscription SomeSubscription { productUpdated { id } }
      GRAPHQL
    end

    it "raises configuration error" do
      expect { subject }.to raise_error(
        GraphQL::AnyCable::ChannelConfigurationError,
        /ActionCable channel wasn't provided in the context for GraphQL query execution!/
      )
    end
  end

  describe ".config" do
    it "returns the default redis_prefix" do
      expect(GraphQL::AnyCable.config.redis_prefix).to eq("graphql")
    end

    context "when changed redis_prefix" do
      after do
        GraphQL::AnyCable.config.redis_prefix = "graphql"
      end

      it "writes a new value to redis_prefix" do
        GraphQL::AnyCable.config.redis_prefix = "new-graphql"

        expect(GraphQL::AnyCable.config.redis_prefix).to eq("new-graphql")
      end
    end
  end

  describe ".stats" do
    it "calls Graphql::AnyCable::Stats" do
      allow_any_instance_of(GraphQL::AnyCable::Stats).to receive(:collect)

      described_class.stats
    end
  end
end
