# frozen_string_literal: true

require "anycable"
require "graphql/subscriptions"
require "graphql/anycable/errors"

# A subscriptions implementation that sends data as AnyCable broadcastings.
#
# Since AnyCable is aimed to be compatible with ActionCable, this adapter
# may be used as (practically) drop-in replacement to ActionCable adapter
# shipped with graphql-ruby.
#
# @example Adding AnyCableSubscriptions to your schema
#   MySchema = GraphQL::Schema.define do
#     use GraphQL::Subscriptions::AnyCableSubscriptions
#   end
#
# @example Implementing a channel for GraphQL Subscriptions
#   class GraphqlChannel < ApplicationCable::Channel
#     def execute(data)
#       query = data["query"]
#       variables = ensure_hash(data["variables"])
#       operation_name = data["operationName"]
#       context = {
#         current_user: current_user,
#         # Make sure the channel is in the context
#         channel: self,
#       }
#
#       result = MySchema.execute({
#         query: query,
#         context: context,
#         variables: variables,
#         operation_name: operation_name
#       })
#
#       payload = {
#         result: result.subscription? ? {data: nil} : result.to_h,
#         more: result.subscription?,
#       }
#
#       transmit(payload)
#     end
#
#     def unsubscribed
#       MySchema.subscriptions.delete_channel_subscriptions(self)
#     end
#   end
#
module GraphQL
  class Subscriptions
    class AnyCableSubscriptions < GraphQL::Subscriptions
      extend Forwardable

      def_delegators :"GraphQL::AnyCable", :subscription_store, :config
      def_delegators :"::AnyCable", :broadcast

      # @param serializer [<#dump(obj), #load(string)] Used for serializing messages before handing them to `.broadcast(msg)`
      def initialize(serializer: Serialize, **rest)
        @serializer = serializer
        super
      end

      # An event was triggered.
      # Re-evaluate all subscribed queries and push the data over ActionCable.
      def execute_all(event, object)
        fingerprints = subscription_store.fingerprints_for_topic(event.topic)
        return if fingerprints.empty?

        fingerprint_subscription_ids = subscription_store.subscription_ids_for_fingerprints(fingerprints)

        fingerprint_subscription_ids.each do |fingerprint, subscription_ids|
          execute_grouped(fingerprint, subscription_ids, event, object)
        end

        # Call to +trigger+ returns this. Convenient for playing in console
        fingerprint_subscription_ids.map { |k, v| [k, v.size] }.to_h
      end

      # The fingerprint has told us that this response should be shared by all subscribers,
      # so just run it once, then deliver the result to every subscriber
      def execute_grouped(fingerprint, subscription_ids, event, object)
        return if subscription_ids.empty?

        subscription_id = subscription_ids.find { |sid| subscription_store.subscription_exists?(sid) }
        return unless subscription_id # All subscriptions has expired but haven't cleaned up yet

        result = execute_update(subscription_id, event, object)
        return unless result

        # Having calculated the result _once_, send the same payload to all subscribers
        deliver(subscription_stream(fingerprint), result)
      end

      # Disable this method as there is no fingerprint (it can be retrieved from subscription though)
      def execute(subscription_id, event, object)
        raise NotImplementedError, "Use execute_all method instead of execute to get actual event fingerprint"
      end

      # This subscription was re-evaluated.
      # Send it to the specific stream where this client was waiting.
      # @param strean_key [String]
      # @param result [#to_h] result to send to clients
      def deliver(stream_key, result)
        payload = {result: result.to_h, more: true}.to_json
        broadcast(stream_key, payload)
      end

      # Save query to storage.
      def write_subscription(query, events)
        context = query.context.to_h
        subscription_id = context.delete(:subscription_id) || build_id
        channel = context.delete(:channel)

        raise GraphQL::AnyCable::ChannelConfigurationError unless channel

        # Store subscription_id in the channel state to cleanup on disconnect
        write_subscription_id(channel, subscription_id)

        events.each do |event|
          channel.stream_from(subscription_stream(event.fingerprint))
        end

        data = {
          query_string: query.query_string,
          variables: query.provided_variables.to_json,
          context: @serializer.dump(context.to_h),
          operation_name: query.operation_name.to_s,
          events: events.map { |e| [e.topic, e.fingerprint] }.to_h.to_json
        }

        subscription_store.write_subscription(
          subscription_id,
          channel_id: subscription_id,
          data: data,
          events: events,
          expiration_seconds: config.subscription_expiration_seconds
        )
      end

      # Return the query from storage.
      def read_subscription(subscription_id)
        subscription = subscription_store.read_subscription(subscription_id)
        return unless subscription

        subscription[:context] = @serializer.load(subscription[:context])
        subscription[:variables] = JSON.parse(subscription[:variables])
        subscription[:operation_name] = nil if subscription[:operation_name].strip == ""
        subscription
      end

      # The channel was closed, forget about it and its subscriptions
      def delete_channel_subscriptions(channel)
        raise(ArgumentError, "Please pass channel instance to #{__method__} in your #unsubscribed method") if channel.is_a?(String)

        channel_id = read_subscription_id(channel)

        # Missing in case disconnect happens before #execute
        return unless channel_id

        subscription_store.delete_channel_subscriptions(channel_id)
      end

      def delete_subscription(subscription_id, redis: nil)
        if redis
          store = GraphQL::AnyCable::SubscriptionStores::Redis.new(redis_connector: ->(&block) { block.call(redis) }, config: config)
          store.delete_subscription(subscription_id, redis: redis)
        else
          subscription_store.delete_subscription(subscription_id)
        end
      end

      private

      def read_subscription_id(channel)
        return channel.instance_variable_get(:@__sid__) if channel.instance_variable_defined?(:@__sid__)

        istate = fetch_channel_istate(channel)

        return unless istate

        channel.instance_variable_set(:@__sid__, istate["sid"])
      end

      def write_subscription_id(channel, val)
        channel.connection.anycable_socket.istate["sid"] = val
        channel.instance_variable_set(:@__sid__, val)
      end

      def fetch_channel_istate(channel)
        # For Rails integration
        return channel.__istate__ if channel.respond_to?(:__istate__)

        return unless channel.connection.socket.istate

        if channel.connection.socket.istate[channel.identifier]
          JSON.parse(channel.connection.socket.istate[channel.identifier])
        else
          channel.connection.socket.istate
        end
      end

      def subscription_stream(fingerprint)
        subscription_store.stream_for(fingerprint)
      end
    end
  end
end
