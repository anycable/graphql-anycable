# frozen_string_literal: true

require "integration_helper"

RSpec.describe "non-broadcastable subscriptions" do
  subject { handler.handle(:command, request) }

  let(:schema) { AnycableSchema }

  let(:query) do
    <<~GQL
      subscription postSubscription($id: ID!) {
        postUpdated(id: $id) {
          post {
            title
          }
        }
      }
    GQL
  end
  let(:variables) { { id: "a" } }

  let(:subscription_payload) { { query: query, variables: variables } }

  let(:command) { "message" }
  let(:data) { { action: "execute", **subscription_payload } }

  before { allow(AnyCable.broadcast_adapter).to receive(:broadcast) }

  describe "execute" do
    it "responds with result" do
      expect(subject).to be_success
      expect(subject.transmissions.size).to eq 1
      expect(subject.transmissions.first).to eq({ result: { data: nil }, more: true }.to_json)
      expect(subject.streams.size).to eq 1
      expect(subject.istate["sid"]).not_to be_nil
    end

    specify "creates uniq stream for each subscription" do
      expect(subject).to be_success
      expect(subject.streams.size).to eq 1

      all_streams = Set.new(subject.streams)

      # update request channelId
      request.identifier = channel_identifier.merge(channelId: rand(1000).to_s).to_json

      response = handler.handle(:command, request)
      expect(response).to be_success
      expect(response.streams.size).to eq 1

      all_streams << response.streams.first
      expect(all_streams.size).to eq 2

      # now update the query param
      request.data = data.merge(variables: { id: "b" }).to_json
      request.identifier = channel_identifier.merge(channelId: rand(1000).to_s).to_json

      response = handler.handle(:command, request)
      expect(response).to be_success
      expect(response.streams.size).to eq 1

      all_streams << response.streams.first
      expect(all_streams.size).to eq 3
    end
  end

  describe "unsubscribe" do
    let(:redis) { AnycableSchema.subscriptions.redis }

    specify "removes subscription from the store" do
      # first, subscribe to obtain the connection state
      subscribe_response = handler.handle(:command, request)
      expect(subscribe_response).to be_success

      expect(redis.keys("graphql-subscription:*").size).to eq(1)

      first_state = subscribe_response.istate

      request.command = "unsubscribe"
      request.data = ""
      request.istate = first_state

      response = handler.handle(:command, request)
      expect(response).to be_success

      expect(redis.keys("graphql-subscription:*").size).to eq(0)
    end

    specify "creates an entry for each subscription" do
      # first, subscribe to obtain the connection state
      response = handler.handle(:command, request)
      expect(response).to be_success

      expect(redis.keys("graphql-subscription:*").size).to eq(1)
      expect(redis.keys("graphql-subscriptions:*").size).to eq(1)

      request_2 = request.dup

      # update request context and channelId
      request_2.connection_identifiers = identifiers.merge(current_user: "alice").to_json
      request_2.identifier = channel_identifier.merge(channelId: rand(1000).to_s).to_json

      response_2 = handler.handle(:command, request_2)

      expect(redis.keys("graphql-subscription:*").size).to eq(2)
      expect(redis.keys("graphql-subscriptions:*").size).to eq(2)

      schema.subscriptions.trigger(:post_updated, { id: "a" }, POSTS.first)
      expect(AnyCable.broadcast_adapter).to have_received(:broadcast).twice

      first_state = response.istate

      request.command = "unsubscribe"
      request.data = ""
      request.istate = first_state

      response = handler.handle(:command, request)
      expect(response).to be_success

      expect(redis.keys("graphql-subscription:*").size).to eq(1)
      expect(redis.keys("graphql-subscriptions:*").size).to eq(1)

      schema.subscriptions.trigger(:post_updated, { id: "a" }, POSTS.first)
      expect(AnyCable.broadcast_adapter).to have_received(:broadcast).thrice

      second_state = response_2.istate

      request_2.command = "unsubscribe"
      request_2.data = ""
      request_2.istate = second_state

      response = handler.handle(:command, request)
      expect(response).to be_success

      expect(redis.keys("graphql-subscription:*").size).to eq(0)
      expect(redis.keys("graphql-subscriptions:*").size).to eq(0)

      schema.subscriptions.trigger(:post_updated, { id: "a" }, POSTS.first)
      expect(AnyCable.broadcast_adapter).to have_received(:broadcast).thrice
    end

    context "with similar ChannelId and not using ID from client" do
      let(:config) { GraphQL::AnyCable.config }

      around do |ex|
        config.use_client_provided_uniq_id.tap do |was_val|
          config.use_client_provided_uniq_id = false
          ex.run
          config.use_client_provided_uniq_id = was_val
        end
      end

      specify "creates an entry for each subscription" do
        # first, subscribe to obtain the connection state
        subscribe_response = handler.handle(:command, request)
        expect(subscribe_response).to be_success

        expect(redis.keys("graphql-subscription:*").size).to eq(1)
        expect(redis.keys("graphql-subscriptions:*").size).to eq(1)

        # update request context
        request.connection_identifiers = identifiers.merge(current_user: "alice").to_json

        response = handler.handle(:command, request)

        expect(redis.keys("graphql-subscription:*").size).to eq(2)
        expect(redis.keys("graphql-subscriptions:*").size).to eq(2)

        istate = response.istate

        request.command = "unsubscribe"
        request.data = ""
        request.istate = istate

        response = handler.handle(:command, request)
        expect(response).to be_success

        expect(redis.keys("graphql-subscription:*").size).to eq(1)
        expect(redis.keys("graphql-subscriptions:*").size).to eq(1)
      end
    end

    context "without subscription" do
      let(:data) { nil }
      let(:command) { "unsubscribe" }

      specify do
        expect(subject).to be_success
      end
    end
  end
end
