# frozen_string_literal: true

RSpec.describe Graphql::Anycable do
  subject do
    AnycableSchema.execute(
      query: "subscription ProductUpdated { productUpdated { id } }",
      context: { channel: channel, subscription_id: subscription_id },
      variables: {},
      operation_name: "ProductUpdated",
    )
  end

  let(:channel) do
    double
  end

  let(:anycable) { AnyCable.broadcast_adapter }

  let(:subscription_id) do
    "some-truly-random-number"
  end

  before do
    allow(channel).to receive(:stream_from)
    allow(channel).to receive(:params).and_return("channelId" => "ohmycables")
    allow(anycable).to receive(:broadcast)
  end

  it "subscribes channel to stream updates from GraphQL subscription" do
    subject
    expect(channel).to have_received(:stream_from).with("graphql-subscription:#{subscription_id}")
  end

  it "broadcasts message when event is being triggered" do
    subject
    AnycableSchema.subscriptions.trigger(:product_updated, {}, { id: 1, title: "foo" })
    expect(anycable).to have_received(:broadcast).with("graphql-subscription:#{subscription_id}", "{\"result\":{\"data\":{\"productUpdated\":{\"id\":\"1\"}}},\"more\":true}")
  end
end
