# frozen_string_literal: true

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
    double("Post", id: 1, title: "Broadcasting…", actions: %w[Edit Delete])
  end

  let(:query) do
    <<~GRAPHQL.strip
      subscription SomeSubscription { postCreated{ id title } }
    GRAPHQL
  end

  let(:anycable) { AnyCable.broadcast_adapter }

  before do
    allow(channel).to receive(:stream_from)
    allow(channel).to receive(:params).and_return("channelId" => "ohmycables")
    allow(anycable).to receive(:broadcast)
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
      expect { BroadcastSchema.subscriptions.trigger(:post_created, {}, object) }.not_to raise_error
      expect(object).to have_received(:title).once
      expect(anycable).to have_received(:broadcast).once
    end
  end
end
