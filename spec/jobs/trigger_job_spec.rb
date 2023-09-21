# frozen_string_literal: true

require "active_job"
require "graphql/jobs/trigger_job"
require "graphql/serializers/anycable_subscription_serializer"

RSpec.describe GraphQL::Jobs::TriggerJob do
  subject(:job) { described_class.perform_later(*job_payload) }
  subject(:trigger_changes) { AnycableSchema.subscriptions.trigger(*trigger_sync_arguments) }

  before(:all) do
    ActiveJob::Serializers.add_serializers(GraphQL::Serializers::AnyCableSubscriptionSerializer)
  end

  before do
    AnycableSchema.execute(
      query: query,
      context: { channel: channel, subscription_id: "some-truly-random-number" },
      variables: {},
      operation_name: "SomeSubscription",
      )
  end

  let(:trigger_sync_arguments) do
    [
      :product_updated,
      {},
      {id: 1, title: "foo"}
    ]
  end

  let(:job_payload) do
    [
      { schema: "AnycableSchema", "serializer": "GraphQL::Subscriptions::Serialize" },
      "trigger_sync",
      *trigger_sync_arguments
    ]
  end

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

  context "when config.delivery_method is active_job" do
    around do |ex|
      old_queue = ActiveJob::Base.queue_adapter
      old_value = GraphQL::AnyCable.config.delivery_method

      GraphQL::AnyCable.config.delivery_method = "active_job"
      ActiveJob::Base.queue_adapter = :inline

      ex.run

      GraphQL::AnyCable.config.delivery_method = old_value
      ActiveJob::Base.queue_adapter = old_queue
    end

    it "executes AnyCableSubscriptions" do
      expect_any_instance_of(GraphQL::Jobs::TriggerJob).to receive(:perform)
      expect(GraphQL::Jobs::TriggerJob).to receive(:set).with(queue: "default").and_call_original

      trigger_changes
    end

    context "when config.queue is 'test'" do
      around do |ex|
        old_queue = GraphQL::AnyCable.config.queue
        GraphQL::AnyCable.config.queue = "test"

        ex.run

        GraphQL::AnyCable.config.queue = old_queue
      end

      it "executes AnyCableSubscriptions" do
        expect_any_instance_of(GraphQL::Jobs::TriggerJob).to receive(:perform)
        expect(GraphQL::Jobs::TriggerJob).to receive(:set).with(queue: "test").and_call_original

        trigger_changes
      end
    end
  end
end

