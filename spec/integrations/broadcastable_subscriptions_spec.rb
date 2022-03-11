# frozen_string_literal: true

require "integration_helper"

RSpec.describe "broadcastable subscriptions" do
  let(:schema) { BroadcastSchema }

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
  let(:variables) { {id: "a"} }

  let(:subscription_payload) { {query: query, variables: variables} }

  let(:command) { "message" }
  let(:data) { {action: "execute", **subscription_payload} }

  subject { handler.handle(:command, request) }

  before { allow(AnyCable.broadcast_adapter).to receive(:broadcast) }

  describe "execute" do
    it "responds with result" do
      expect(subject).to be_success
      expect(subject.transmissions.size).to eq 1
      expect(subject.transmissions.first).to eq({result: {data: nil}, more: true}.to_json)
      expect(subject.streams.size).to eq 1
      expect(subject.istate["sid"]).not_to be_nil
    end

    specify "streams depends only on query params and the same for equal subscriptions" do
      expect(subject).to be_success
      expect(subject.streams.size).to eq 1

      stream_name = subject.streams.first

      # update request context
      request.connection_identifiers = identifiers.merge(current_user: "alice").to_json

      response = handler.handle(:command, request)
      expect(response).to be_success
      expect(response.streams).to eq([stream_name])

      # now update the query param
      request.data = data.merge(variables: {id: "b"}).to_json

      response = handler.handle(:command, request)
      expect(response).to be_success
      expect(response.streams.size).to eq 1
      expect(response.streams.first).not_to eq stream_name
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

    context "with nested istate" do
      specify "removes subscription from the store" do
        # first, subscribe to obtain the connection state
        subscribe_response = handler.handle(:command, request)
        expect(subscribe_response).to be_success
  
        expect(redis.keys("graphql-subscription:*").size).to eq(1)
  
        istate = subscribe_response.istate
  
        request.command = "unsubscribe"
        request.data = ""
        request.istate[channel_id] = istate.to_h.to_json
  
        response = handler.handle(:command, request)
        expect(response).to be_success
  
        expect(redis.keys("graphql-subscription:*").size).to eq(0)
      end
    end

    specify "creates single entry for similar subscriptions" do
      # first, subscribe to obtain the connection state
      response = handler.handle(:command, request)
      expect(response).to be_success

      expect(redis.keys("graphql-subscription:*").size).to eq(1)
      expect(redis.keys("graphql-subscriptions:*").size).to eq(1)

      request_2 = request.dup

      # update request context
      request_2.connection_identifiers = identifiers.merge(current_user: "alice").to_json

      response_2 = handler.handle(:command, request_2)

      expect(redis.keys("graphql-subscription:*").size).to eq(2)
      expect(redis.keys("graphql-subscriptions:*").size).to eq(1)

      schema.subscriptions.trigger(:post_updated, {id: "a"}, POSTS.first)
      expect(AnyCable.broadcast_adapter).to have_received(:broadcast).once

      first_state = response.istate

      request.command = "unsubscribe"
      request.data = ""
      request.istate = first_state

      response = handler.handle(:command, request)
      expect(response).to be_success

      expect(redis.keys("graphql-subscription:*").size).to eq(1)
      expect(redis.keys("graphql-subscriptions:*").size).to eq(1)

      schema.subscriptions.trigger(:post_updated, {id: "a"}, POSTS.first)
      expect(AnyCable.broadcast_adapter).to have_received(:broadcast).twice

      second_state = response_2.istate

      request_2.command = "unsubscribe"
      request_2.data = ""
      request_2.istate = second_state

      response = handler.handle(:command, request)
      expect(response).to be_success

      expect(redis.keys("graphql-subscription:*").size).to eq(0)
      expect(redis.keys("graphql-subscriptions:*").size).to eq(0)

      schema.subscriptions.trigger(:post_updated, {id: "a"}, POSTS.first)
      expect(AnyCable.broadcast_adapter).to have_received(:broadcast).twice
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
