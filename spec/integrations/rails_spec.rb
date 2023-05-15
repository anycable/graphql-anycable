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
require "action_cable/server"
require "action_cable/server/base"
# Only for anycable-rails <1.3.0
unless defined?(AnyCable::Rails::Connection)
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

    # rubocop:disable Metrics/MethodLength
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
          more: result.subscription?,
        },
      )
    end
    # rubocop:enable Metrics/MethodLength

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
  let(:variables) { { id: "a" } }
  let(:subscription_payload) { { query: query, variables: variables } }
  let(:command) { "message" }
  let(:data) { { action: "execute", **subscription_payload } }
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
  let(:channel_class) { "ApplicationCable::GraphqlChannel" }

  before do
    if defined?(AnyCable::Rails::Connection)
      allow(AnyCable).to receive(:connection_factory)
        .and_return(lambda { |socket, **options|
                      AnyCable::Rails::Connection.new(ApplicationCable::Connection, socket, **options)
                    })
    else
      allow(AnyCable).to receive(:connection_factory)
        .and_return(->(socket, **options) { ApplicationCable::Connection.call(socket, **options) })
    end
    allow(AnyCable.broadcast_adapter).to receive(:broadcast)
  end

  it "execute multiple clients + trigger + disconnect one by one" do
    # first, subscribe to obtain the connection state
    response = handler.handle(:command, request)
    expect(response).to be_success

    expect(redis.keys("graphql-subscription:*").size).to eq(1)
    expect(redis.keys("graphql-subscriptions:*").size).to eq(1)

    request2 = request.dup

    # update request context and channelId
    request2.connection_identifiers = identifiers.merge(current_user: "alice").to_json
    request2.identifier = channel_identifier.merge(channelId: rand(1000).to_s).to_json

    response2 = handler.handle(:command, request2)

    expect(redis.keys("graphql-subscription:*").size).to eq(2)
    expect(redis.keys("graphql-subscriptions:*").size).to eq(1)

    schema.subscriptions.trigger(:post_updated, { id: "a" }, POSTS.first)
    expect(AnyCable.broadcast_adapter).to have_received(:broadcast).once

    first_state = response.istate

    request.command = "unsubscribe"
    request.data = ""
    request.istate = first_state

    response = handler.handle(:command, request)
    expect(response).to be_success

    expect(redis.keys("graphql-subscription:*").size).to eq(1)
    expect(redis.keys("graphql-subscriptions:*").size).to eq(1)

    schema.subscriptions.trigger(:post_updated, { id: "a" }, POSTS.first)
    expect(AnyCable.broadcast_adapter).to have_received(:broadcast).twice

    second_state = response2.istate

    # Disconnect the second one via #disconnect call
    disconnect_request = AnyCable::DisconnectRequest.new(
      identifiers: request2.connection_identifiers,
      subscriptions: [request2.identifier],
      env: request2.env,
    )

    disconnect_request.istate[request2.identifier] = second_state.to_h.to_json

    disconnect_response = handler.handle(:disconnect, disconnect_request)
    expect(disconnect_response).to be_success

    expect(redis.keys("graphql-subscription:*").size).to eq(0)
    expect(redis.keys("graphql-subscriptions:*").size).to eq(0)

    schema.subscriptions.trigger(:post_updated, { id: "a" }, POSTS.first)
    expect(AnyCable.broadcast_adapter).to have_received(:broadcast).twice
  end
end
