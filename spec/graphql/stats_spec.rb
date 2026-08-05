# frozen_string_literal: true

RSpec.describe GraphQL::AnyCable::Stats do
  describe "#collect" do
    let(:query) do
      <<~GRAPHQL
        subscription SomeSubscription {
          productUpdated { id }
        }
      GRAPHQL
    end

    let(:query2) do
      <<~GRAPHQL
        subscription SomeSubscription {
          productCreated { id title }
        }
      GRAPHQL
    end

    let(:channel) do
      socket = double("Socket", istate: AnyCable::Socket::State.new({}))
      connection = double("Connection", anycable_socket: socket)
      double("Channel", __istate__: socket.istate, id: "legacy_id", params: {"channelId" => "legacy_id"}, stream_from: nil, connection: connection)
    end

    let(:subscription_id) do
      "some-truly-random-number"
    end

    before do
      res = AnycableSchema.execute(
        query: query,
        context: {channel: channel, subscription_id: subscription_id},
        variables: {},
        operation_name: "SomeSubscription"
      )
      expect(res.to_h.fetch("errors", [])).to be_empty

      res2 = AnycableSchema.execute(
        query: query2,
        context: {channel: channel, subscription_id: subscription_id},
        variables: {},
        operation_name: "SomeSubscription"
      )
      expect(res2.to_h.fetch("errors", [])).to be_empty
    end

    context "when include_subscriptions is false" do
      let(:expected_result) do
        {total: {subscription: 1, fingerprints: 2, subscriptions: 2, channel: 1}}
      end

      it "returns total stat" do
        expect(subject.collect).to eq(expected_result)
      end
    end

    context "when include_subscriptions is true" do
      subject { described_class.new(include_subscriptions: true) }

      let(:expected_result) do
        {
          total: {subscription: 1, fingerprints: 2, subscriptions: 2, channel: 1},
          subscriptions: {
            "productCreated" => 1,
            "productUpdated" => 1
          }
        }
      end

      it "returns total stat with grouped subscription stats" do
        expect(subject.collect).to eq(expected_result)
      end
    end
  end
end
