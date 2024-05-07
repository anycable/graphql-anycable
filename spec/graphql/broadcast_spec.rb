# frozen_string_literal: true

require "active_job"
require "graphql/jobs/trigger_job"
require "graphql/serializers/anycable_subscription_serializer"

RSpec.describe "Broadcasting" do
  def subscribe(query)
    BroadcastSchema.execute(
      query: query,
      context: { channel: channel },
      variables: {},
      operation_name: "SomeSubscription",
    )
  end

  let(:channel) do
    socket = double("Socket", istate: AnyCable::Socket::State.new({}))
    connection = double("Connection", anycable_socket: socket)
    double("Channel", connection: connection)
  end

  let(:object) do
    double("article", id: 1, title: "Broadcasting…", actions: %w[Edit Delete]).extend(GlobalID::Identification)
  end

  let(:query) do
    <<~GRAPHQL.strip
      subscription SomeSubscription { postCreated{ id title } }
    GRAPHQL
  end

  let(:anycable) { AnyCable.broadcast_adapter }

  before do
    allow(channel).to receive(:stream_from)
    allow(anycable).to receive(:broadcast)
    allow(GlobalID).to receive(:app).and_return("example")
    allow(RSpec::Mocks::Double).to receive(:find).and_return(object)
  end

  context "when config.deliver_method is active_job" do
    before(:all) do
      ActiveJob::Serializers.add_serializers(GraphQL::Serializers::AnyCableSubscriptionSerializer)
    end

    around(:all) do |ex|
      old_queue = ActiveJob::Base.queue_adapter
      old_value = GraphQL::AnyCable.config.delivery_method

      GraphQL::AnyCable.config.delivery_method = "active_job"
      ActiveJob::Base.queue_adapter = :inline

      ex.run

      GraphQL::AnyCable.config.delivery_method = old_value
      ActiveJob::Base.queue_adapter = old_queue
    end

    context "when all clients asks for broadcastable fields only" do
      let(:query) do
        <<~GRAPHQL.strip
          subscription SomeSubscription { postCreated{ id title } }
        GRAPHQL
      end

      it "uses broadcasting to resolve query only once" do
        2.times { subscribe(query) }
        expect_any_instance_of(GraphQL::Jobs::TriggerJob).to receive(:perform).and_call_original

        BroadcastSchema.subscriptions.trigger(:post_created, {}, object)

        expect(object).to have_received(:title).once
        expect(anycable).to have_received(:broadcast).once
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

        expect_any_instance_of(GraphQL::Jobs::TriggerJob).to receive(:perform).and_call_original

        BroadcastSchema.subscriptions.trigger(:post_created, {}, object)
        expect(object).to have_received(:title).twice
        expect(anycable).to have_received(:broadcast).twice
      end
    end

    context "when one of subscriptions got expired" do
      let(:query) do
        <<~GRAPHQL.strip
          subscription SomeSubscription { postCreated{ id title } }
        GRAPHQL
      end

      let(:redis) { AnycableSchema.subscriptions.redis }

      it "doesn't fail" do
        3.times { subscribe(query) }
        redis.keys("graphql-subscription:*").last.tap(&redis.method(:del))
        expect(redis.keys("graphql-subscription:*").size).to eq(2)

        expect_any_instance_of(GraphQL::Jobs::TriggerJob).to receive(:perform).and_call_original

        expect { BroadcastSchema.subscriptions.trigger(:post_created, {}, object) }.not_to raise_error
        expect(object).to have_received(:title).once
        expect(anycable).to have_received(:broadcast).once
      end
    end
  end

  context "when config.deliver_method is inline" do
    around(:all) do |ex|
      old_queue = ActiveJob::Base.queue_adapter
      old_value = GraphQL::AnyCable.config.delivery_method

      GraphQL::AnyCable.config.delivery_method = "inline"
      ActiveJob::Base.queue_adapter = :test

      ex.run

      GraphQL::AnyCable.config.delivery_method = old_value
      ActiveJob::Base.queue_adapter = old_queue
    end

    context "when all clients asks for broadcastable fields only" do
      let(:query) do
        <<~GRAPHQL.strip
          subscription SomeSubscription { postCreated{ id title } }
        GRAPHQL
      end

      it "uses broadcasting to resolve query only once" do
        2.times { subscribe(query) }

        expect_any_instance_of(GraphQL::Jobs::TriggerJob).to_not receive(:perform)

        BroadcastSchema.subscriptions.trigger(:post_created, {}, object)
        expect(object).to have_received(:title).once
        expect(anycable).to have_received(:broadcast).once
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

        expect_any_instance_of(GraphQL::Jobs::TriggerJob).to_not receive(:perform)

        BroadcastSchema.subscriptions.trigger(:post_created, {}, object)
        expect(object).to have_received(:title).twice
        expect(anycable).to have_received(:broadcast).twice
      end
    end

    context "when one of subscriptions got expired" do
      let(:query) do
        <<~GRAPHQL.strip
          subscription SomeSubscription { postCreated{ id title } }
        GRAPHQL
      end

      let(:redis) { AnycableSchema.subscriptions.redis }

      it "doesn't fail" do
        3.times { subscribe(query) }
        redis.keys("graphql-subscription:*").last.tap(&redis.method(:del))
        expect(redis.keys("graphql-subscription:*").size).to eq(2)

        expect_any_instance_of(GraphQL::Jobs::TriggerJob).to_not receive(:perform)

        expect { BroadcastSchema.subscriptions.trigger(:post_created, {}, object) }.not_to raise_error
        expect(object).to have_received(:title).once
        expect(anycable).to have_received(:broadcast).once
      end
    end
  end
end
