# frozen_string_literal: true

require "anycable"
require "graphql/subscriptions"

# rubocop: disable Metrics/AbcSize, Metrics/LineLength, Metrics/MethodLength

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
#       channel_id = params.fetch("channelId")
#       MySchema.subscriptions.delete_channel_subscriptions(channel_id)
#     end
#   end
#
module GraphQL
  class Subscriptions
    class AnyCableSubscriptions < GraphQL::Subscriptions
      extend Forwardable

      def_delegators :"GraphQL::Anycable", :redis

      SUBSCRIPTION_PREFIX = "graphql-subscription:"
      SUBSCRIPTION_EVENTS_PREFIX = "graphql-subscription-events:"
      EVENT_PREFIX = "graphql-event:"
      CHANNEL_PREFIX = "graphql-channel:"

      # @param serializer [<#dump(obj), #load(string)] Used for serializing messages before handing them to `.broadcast(msg)`
      def initialize(serializer: Serialize, **rest)
        @serializer = serializer
        super
      end

      # An event was triggered.
      # Re-evaluate all subscribed queries and push the data over ActionCable.
      def execute_all(event, object)
        redis.smembers(EVENT_PREFIX + event.topic).each do |subscription_id|
          next unless redis.exists(SUBSCRIPTION_PREFIX + subscription_id)
          execute(subscription_id, event, object)
        end
      end

      # This subscription was re-evaluated.
      # Send it to the specific stream where this client was waiting.
      def deliver(subscription_id, result)
        payload = { result: result.to_h, more: true }
        anycable.broadcast(SUBSCRIPTION_PREFIX + subscription_id, payload.to_json)
      end

      # Save query to "storage" (in redis)
      def write_subscription(query, events)
        context = query.context.to_h
        subscription_id = context[:subscription_id] ||= build_id
        channel = context.delete(:channel)
        stream = context[:action_cable_stream] ||= SUBSCRIPTION_PREFIX + subscription_id
        channel.stream_from(stream)

        data = {
          query_string: query.query_string,
          variables: query.provided_variables.to_json,
          context: @serializer.dump(context.to_h),
          operation_name: query.operation_name,
        }

        redis.multi do
          redis.sadd(CHANNEL_PREFIX + channel.params["channelId"], subscription_id)
          redis.mapped_hmset(SUBSCRIPTION_PREFIX + subscription_id, data)
          redis.sadd(SUBSCRIPTION_EVENTS_PREFIX + subscription_id, *events.map(&:topic))
          events.each do |event|
            redis.sadd(EVENT_PREFIX + event.topic, subscription_id)
          end
          next unless config.subscription_expiration_seconds
          redis.expire(CHANNEL_PREFIX + channel.params["channelId"], config.subscription_expiration_seconds)
          redis.expire(SUBSCRIPTION_PREFIX + subscription_id, config.subscription_expiration_seconds)
        end
      end

      # Return the query from "storage" (in redis)
      def read_subscription(subscription_id)
        redis.mapped_hmget(
          "#{SUBSCRIPTION_PREFIX}#{subscription_id}",
          :query_string, :variables, :context, :operation_name,
        ).tap do |subscription|
          subscription[:context]   = @serializer.load(subscription[:context])
          subscription[:variables] = JSON.parse(subscription[:variables])
        end
      end

      # The channel was closed, forget about it.
      def delete_subscription(subscription_id)
        # Remove subscription ids from all events
        events = redis.smembers(SUBSCRIPTION_EVENTS_PREFIX + subscription_id)
        events.each do |event_topic|
          redis.srem(EVENT_PREFIX + event_topic, subscription_id)
        end
        # Delete subscription itself
        redis.del(SUBSCRIPTION_EVENTS_PREFIX + subscription_id)
        redis.del(SUBSCRIPTION_PREFIX + subscription_id)
      end

      def delete_channel_subscriptions(channel_id)
        redis.smembers(CHANNEL_PREFIX + channel_id).each do |subscription_id|
          delete_subscription(subscription_id)
        end
        redis.del(CHANNEL_PREFIX + channel_id)
      end

      private

      def anycable
        @anycable ||= ::Anycable.broadcast_adapter
      end

      def config
        @config ||= GraphQL::Anycable::Config.new
      end
    end
  end
end
# rubocop: enable Metrics/AbcSize, Metrics/LineLength, Metrics/MethodLength
