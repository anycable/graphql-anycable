# frozen_string_literal: true

RSpec.describe GraphQL::AnyCable do
  subject do
    AnycableSchema.execute(
      query: query,
      context: { channel: channel, subscription_id: subscription_id },
      variables: {},
      operation_name: "SomeSubscription",
    )
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
    double("Channel", id: "ohmycables", params: { "channelId" => "ohmycables" }, stream_from: nil)
  end

  let(:anycable) { AnyCable.broadcast_adapter }

  let(:subscription_id) do
    "some-truly-random-number"
  end

  let(:fingerprint) do
    ":productUpdated:/SomeSubscription/fBDZmJU1UGTorQWvOyUeaHVwUxJ3T9SEqnetj6SKGXc=/0/RBNvo1WzZ4oRRq0W9-hknpT7T8If536DEMBg9hyq_4o="
  end

  before do
    allow(anycable).to receive(:broadcast)
    allow_any_instance_of(GraphQL::Subscriptions::Event).to receive(:fingerprint).and_return(fingerprint)
  end

  it "subscribes channel to stream updates from GraphQL subscription" do
    subject
    expect(channel).to have_received(:stream_from).with("graphql-subscriptions:#{fingerprint}")
  end

  it "broadcasts message when event is being triggered" do
    subject
    AnycableSchema.subscriptions.trigger(:product_updated, {}, { id: 1, title: "foo" })
    expect(anycable).to have_received(:broadcast).with("graphql-subscriptions:#{fingerprint}", expected_result)
  end

  context "with multiple subscriptions in one query" do
    let(:query) do
      <<~GRAPHQL
        subscription SomeSubscription {
          productCreated { id title }
          productUpdated { id }
        }
      GRAPHQL
    end

    context "triggering update event" do
      it "broadcasts message only for update event" do
        subject
        AnycableSchema.subscriptions.trigger(:product_updated, {}, { id: 1, title: "foo" })
        expect(anycable).to have_received(:broadcast).with("graphql-subscriptions:#{fingerprint}", expected_result)
      end
    end

    context "triggering create event" do
      let(:expected_result) do
        <<~JSON.strip
          {"result":{"data":{"productCreated":{"id":"1","title":"Gravizapa"}}},"more":true}
        JSON
      end

      it "broadcasts message only for create event" do
        subject
        AnycableSchema.subscriptions.trigger(:product_created, {}, { id: 1, title: "Gravizapa" })

        expect(anycable).to have_received(:broadcast).with("graphql-subscriptions:#{fingerprint}", expected_result)
      end
    end
  end

  describe ".delete_channel_subscriptions" do
    before do
      AnycableSchema.execute(
        query: query,
        context: { channel: channel, subscription_id: subscription_id },
        variables: {},
        operation_name: "SomeSubscription",
      )
    end

    let(:redis) { AnycableSchema.subscriptions.redis }

    subject do
      AnycableSchema.subscriptions.delete_channel_subscriptions(channel.id)
    end

    it "removes subscription from redis" do
      expect(redis.exists?("graphql-subscription:some-truly-random-number")).to be true
      expect(redis.exists?("graphql-channel:ohmycables")).to be true
      expect(redis.exists?("graphql-fingerprints::productUpdated:")).to be true
      subject
      expect(redis.exists?("graphql-channel:ohmycables")).to be false
      expect(redis.zcard("graphql-fingerprints::productUpdated:")).to be_zero # Seems to be fakeredis bug
      expect(redis.exists?("graphql-subscription:some-truly-random-number")).to be false
    end
  end
end
