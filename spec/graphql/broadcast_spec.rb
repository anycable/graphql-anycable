# frozen_string_literal: true

RSpec.describe "Broadcasting" do
  def subscribe(query)
    BroadcastSchema.execute(
      query: query,
      context: {channel: channel},
      variables: {},
      operation_name: "SomeSubscription"
    )
  end

  let(:channel) do
    socket = double("Socket", istate: AnyCable::Socket::State.new({}))
    connection = double("Connection", anycable_socket: socket)
    double("Channel", __istate__: socket.istate, connection: connection)
  end

  let(:object) do
    double("Post", id: 1, title: "Broadcasting…", actions: %w[Edit Delete])
  end

  let(:query) do
    <<~GRAPHQL.strip
      subscription SomeSubscription { postCreated{ id title } }
    GRAPHQL
  end

  before do
    allow(channel).to receive(:stream_from)
    allow(AnyCable).to receive(:broadcast)
  end

  context "when all clients asks for broadcastable fields only" do
    let(:query) do
      <<~GRAPHQL.strip
        subscription SomeSubscription { postCreated{ id title } }
      GRAPHQL
    end

    it "uses broadcasting to resolve query only once" do
      2.times { subscribe(query) }
      BroadcastSchema.subscriptions.trigger(:post_created, {}, object)
      expect(object).to have_received(:title).once
      expect(AnyCable).to have_received(:broadcast).once
    end
  end

  context "when all clients asks for non-broadcastable fields" do
    let(:query) do
      <<~GRAPHQL.strip
        subscription SomeSubscription { postCreated{ id title actions } }
      GRAPHQL
    end

    it "resolves query for every client" do
      2.times { subscribe(query) }
      BroadcastSchema.subscriptions.trigger(:post_created, {}, object)
      expect(object).to have_received(:title).twice
      expect(AnyCable).to have_received(:broadcast).twice
    end
  end

  context "when one of subscriptions got expired" do
    let(:query) do
      <<~GRAPHQL.strip
        subscription SomeSubscription { postCreated{ id title } }
      GRAPHQL
    end

    let(:redis) { $redis }

    it "doesn't fail" do
      3.times { subscribe(query) }
      redis.keys("graphql-subscription:*").last.tap(&redis.method(:del))
      expect(redis.keys("graphql-subscription:*").size).to eq(2)
      expect { BroadcastSchema.subscriptions.trigger(:post_created, {}, object) }.not_to raise_error
      expect(object).to have_received(:title).once
      expect(AnyCable).to have_received(:broadcast).once
    end
  end

  describe "#execute_grouped" do
    let(:query) do
      <<~GRAPHQL.strip
        subscription SomeSubscription { postCreated{ id } }
      GRAPHQL
    end

    let(:redis) { $redis }
    let(:object) { double("Post", id: 1) }
    let(:subscriptions) { BroadcastSchema.subscriptions }
    let(:event) do
      GraphQL::Subscriptions::Event.new(
        name: "postCreated",
        arguments: {},
        field: BroadcastSchema.subscription.fields["postCreated"],
        scope: nil,
        context: {}
      )
    end
    # A hand-built event can't compute its own fingerprint (it has no query), so take the
    # one the subscriptions were actually stored under. #execute_grouped is given it anyway.
    let(:fingerprint) { redis.zrange("graphql-fingerprints:#{event.topic}", 0, -1).first }
    let(:subscription_ids) { redis.smembers("graphql-subscriptions:#{fingerprint}") }

    subject(:execute_grouped) do
      subscriptions.execute_grouped(fingerprint, subscription_ids, event, object)
    end

    before do
      3.times { subscribe(query) }
      expect(subscription_ids.size).to eq(3)
    end

    context "when a subscription expires before being read" do
      before do
        expired_subscription_id = subscription_ids.first

        allow(subscriptions).to receive(:read_subscription).and_wrap_original do |original, subscription_id|
          redis.del("graphql-subscription:#{subscription_id}") if subscription_id == expired_subscription_id
          original.call(subscription_id)
        end
      end

      it "broadcasts the result using another subscription" do
        execute_grouped

        expect(AnyCable).to have_received(:broadcast).with(
          "graphql-subscriptions:#{fingerprint}",
          '{"result":{"data":{"postCreated":{"id":"1"}}},"more":true}'
        ).once
        expect(object).to have_received(:id).once
        expect(subscriptions).to have_received(:read_subscription).twice
      end

      it "never holds a Redis connection while checking out another one" do
        checked_out = false

        allow(GraphQL::AnyCable).to receive(:with_redis).and_wrap_original do |original, &block|
          raise "Redis connection checked out reentrantly, a small pool would deadlock here" if checked_out

          checked_out = true
          begin
            original.call(&block)
          ensure
            checked_out = false
          end
        end

        expect { execute_grouped }.not_to raise_error
      end
    end

    context "when the update is skipped" do
      before do
        expect_any_instance_of(Broadcastable::PostCreated).to receive(:update).once
          .and_return(GraphQL::Schema::Subscription::NO_UPDATE)
      end

      it "does not execute another subscription" do
        execute_grouped

        expect(AnyCable).not_to have_received(:broadcast)
      end

      it "does not retry when the subscription expires after the update" do
        allow(subscriptions).to receive(:execute_update).and_wrap_original do |original, subscription_id, *args|
          result = original.call(subscription_id, *args)
          redis.del("graphql-subscription:#{subscription_id}")
          result
        end

        execute_grouped

        expect(subscriptions).to have_received(:execute_update).once
        expect(AnyCable).not_to have_received(:broadcast)
      end
    end

    context "when a subscriber unsubscribes instead of updating" do
      let(:executed_updates) { [] }

      before do
        allow_any_instance_of(Broadcastable::PostCreated).to receive(:update) do |subscription|
          executed_updates << subscription
          subscription.unsubscribe
        end
      end

      # #unsubscribe deletes the subscription and returns no result, which looks exactly
      # like an expired one. Retrying there would re-run the query for the whole group.
      it "does not execute another subscription" do
        execute_grouped

        expect(executed_updates.size).to eq(1)
        expect(AnyCable).not_to have_received(:broadcast)
      end
    end

    context "when every subscription expires before being read" do
      before do
        allow(subscriptions).to receive(:execute_update).and_call_original
        allow(subscriptions).to receive(:read_subscription).and_wrap_original do |original, subscription_id|
          redis.del("graphql-subscription:#{subscription_id}")
          original.call(subscription_id)
        end
      end

      it "returns without broadcasting" do
        execute_grouped

        expect(subscriptions).to have_received(:execute_update).exactly(3).times
        expect(AnyCable).not_to have_received(:broadcast)
      end
    end
  end
end
