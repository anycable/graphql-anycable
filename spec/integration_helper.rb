# frozen_string_literal: true

require "anycable/rspec"
require "rack"

RSpec.shared_context "with rpc" do
  include_context "anycable:rpc:command"

  let(:user) { "john" }
  let(:schema) { nil }
  let(:identifiers) { { current_user: "john", schema: schema.to_s } }
  let(:channel_class) { "GraphqlChannel" }
  let(:channel_params) { { channelId: rand(1000).to_s } }
  let(:channel_identifier) { { channel: channel_class }.merge(channel_params) }
  let(:channel_id) { channel_identifier.to_json }

  let(:handler) { AnyCable::RPC::Handler.new }
end

# Minimal AnyCable connection implementation
class FakeConnection
  class Channel
    attr_reader :connection, :params, :identifier

    def initialize(connection, identifier, params)
      @connection = connection
      @identifier = identifier
      @params = params
    end

    def stream_from(broadcasting)
      connection.socket.subscribe identifier, broadcasting
    end
  end

  attr_reader :request, :socket, :identifiers, :subscriptions,
              :schema

  alias anycable_socket socket

  def initialize(socket, identifiers: nil, subscriptions: nil)
    @socket = socket
    @identifiers = identifiers ? JSON.parse(identifiers) : {}
    @request = Rack::Request.new(socket.env)
    @schema = Object.const_get(@identifiers["schema"])
    @subscriptions = subscriptions
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def handle_channel_command(identifier, command, data)
    parsed_id = JSON.parse(identifier)

    parsed_id.delete("channel")
    channel = Channel.new(self, identifier, parsed_id)

    case command
    when "message"
      data = JSON.parse(data)
      result =
        schema.execute(
          query: data["query"],
          context: identifiers.merge(channel: channel),
          variables: Hash(data["variables"]),
          operation_name: data["operationName"],
        )

      transmit(
        result: result.subscription? ? { data: nil } : result.to_h,
        more: result.subscription?,
      )
    when "unsubscribe"
      schema.subscriptions.delete_channel_subscriptions(channel)
      true
    else
      raise "Unknown command"
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def transmit(data)
    socket.transmit data.to_json
  end

  def identifiers_json
    @identifiers.to_json
  end

  def close
    socket.close
  end
end

AnyCable.connection_factory = ->(socket, **options) { FakeConnection.new(socket, **options) }

# Add verbose logging to exceptions
AnyCable.capture_exception do |ex, method, message|
  $stdout.puts "RPC ##{method} failed: #{message}\n#{ex}\n#{ex.backtrace.take(5).join("\n")}"
end

RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{spec/integrations/}) do |metadata|
    metadata[:integration] = true
  end

  config.include_context "with rpc", integration: true
end
