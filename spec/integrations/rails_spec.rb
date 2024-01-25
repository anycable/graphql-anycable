# frozen_string_literal: true

require "integration_helper"
require "rails"
require "action_cable/engine"

# Stub Rails.root for Anyway Config
module Rails
  def self.root
    Pathname.new(__dir__)
  end
end

require "anycable-rails"

# Load server to trigger load hooks
require "action_cable/server/base"
# Only for anycable-rails <1.3.0
unless defined?(::AnyCable::Rails::Connection)
  require "anycable/rails/channel_state"
  require "anycable/rails/actioncable/connection"
end

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :schema

    def schema_class
      schema.constantize
    end
  end

  class GraphqlChannel < ActionCable::Channel::Base
    delegate :schema_class, to: :connection

    def execute(data)
      result = 
        schema_class.execute(
          query: data["query"],
          context: context,
          variables: Hash(data["variables"]),
          operation_name: data["operationName"],
        )

      transmit(
        {
          result: result.subscription? ? { data: nil } : result.to_h,
          more: result.subscription?
        }
      )
    end

    def unsubscribed
      schema_class.subscriptions.delete_channel_subscriptions(self)
    end

    private

    def context
      {
        current_user: connection.current_user,
        channel: self,
      }
    end
  end
end

RSpec.describe "Rails integration" do
  let(:schema) { BroadcastSchema }
  let(:channel_class) { "ApplicationCable::GraphqlChannel" }

  if defined?(::AnyCable::Rails::Connection)
    before do
      allow(AnyCable).to receive(:connection_factory)
        .and_return(->(socket, **options) { ::AnyCable::Rails::Connection.new(ApplicationCable::Connection, socket, **options) })
    end
  else
    before do
      allow(AnyCable).to receive(:connection_factory)
        .and_return(->(socket, **options) { ApplicationCable::Connection.call(socket, **options) })
    end
  end

  let(:variables) { {id: "a"} }

  let(:subscription_payload) { {query: query, variables: variables} }

  let(:command) { "message" }
  let(:data) { {action: "execute", **subscription_payload} }

  subject { handler.handle(:command, request) }

  before { allow(AnyCable.broadcast_adapter).to receive(:broadcast) }

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

  let(:redis) { AnycableSchema.subscriptions.redis }

  it "execute multiple clients + trigger + disconnect one by one" do
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

    # Disconnect the second one via #disconnect call
    disconnect_request = AnyCable::DisconnectRequest.new(
      identifiers: request_2.connection_identifiers,
      subscriptions: [request_2.identifier],
      env: request_2.env
    )

    disconnect_request.istate[request_2.identifier] = second_state.to_h.to_json

    disconnect_response = handler.handle(:disconnect, disconnect_request)
    expect(disconnect_response).to be_success

    expect(redis.keys("graphql-subscription:*").size).to eq(0)
    expect(redis.keys("graphql-subscriptions:*").size).to eq(0)

    schema.subscriptions.trigger(:post_updated, {id: "a"}, POSTS.first)
    expect(AnyCable.broadcast_adapter).to have_received(:broadcast).twice
  end
end
