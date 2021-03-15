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

      def_delegators :"GraphQL::AnyCable", :redis, :config

      SUBSCRIPTION_PREFIX = "graphql-subscription:" # Stores subscription data: query, context, …
      FINGERPRINTS_PREFIX = "graphql-fingerprints:"  # To get fingerprints by topic
      SUBSCRIPTIONS_PREFIX = "graphql-subcriptions:" # To get subscriptions by fingerprint
      CHANNEL_PREFIX = "graphql-channel:" # Auxiliary structure for whole channel's subscriptions cleanup
      # For backward compatibility:
      EVENT_PREFIX = "graphql-event:"
      SUBSCRIPTION_EVENTS_PREFIX = "graphql-subscription-events:"

      # @param serializer [<#dump(obj), #load(string)] Used for serializing messages before handing them to `.broadcast(msg)`
      def initialize(serializer: Serialize, **rest)
        @serializer = serializer
        super
      end

      # An event was triggered.
      # Re-evaluate all subscribed queries and push the data over ActionCable.
      def execute_all(event, object)
        execute_legacy(event, object) if config.handle_legacy_subscriptions

        fingerprints = redis.smembers(FINGERPRINTS_PREFIX + event.topic)
        return if fingerprints.empty?

        grouped_subscription_ids =
          redis.pipelined do
            fingerprints.map do |fingerprint|
              redis.smembers(SUBSCRIPTIONS_PREFIX + fingerprint)
            end
          end

        grouped_subscription_ids.each do |subscription_ids|
          execute_grouped(subscription_ids, event, object)
        end
      end

      def execute_grouped(subscription_ids, event, object)
        return if subscription_ids.empty?

        # The fingerprint has told us that this response should be shared by all subscribers,
        # so just run it once, then deliver the result to every subscriber
        result = execute_update(subscription_ids.first, event, object)
        # Having calculated the result _once_, send the same payload to all subscribers
        payload = prepare_payload(result)
        redis.pipelined do # Here we rely on the fact that anycable broadcast does only Redis PUBLISH and nothing else
          subscription_ids.each do |subscription_id|
            deliver(subscription_id, payload)
          end
        end
      end

      # For migration from pre-1.0 graphql-anycable gem
      def execute_legacy(event, object)
        redis.smembers(EVENT_PREFIX + event.topic).each do |subscription_id|
          next unless redis.exists?(SUBSCRIPTION_PREFIX + subscription_id)
          execute(subscription_id, event, object)
        end
      end

      # Redefine this method as we want to pass already jsonified string to our +deliver+ implementation
      def execute(subscription_id, event, object)
        res = execute_update(subscription_id, event, object)
        if !res.nil?
          deliver(subscription_id, prepare_payload(res))
        end
      end

      # This subscription was re-evaluated.
      # Send it to the specific stream where this client was waiting.
      # @param subscription_id [String]
      # @param payload [String] JSON-encoded result to send to clients
      def deliver(subscription_id, payload)
        anycable.broadcast(SUBSCRIPTION_PREFIX + subscription_id, payload)
      end

      # Save query to "storage" (in redis)
      def write_subscription(query, events)
        context = query.context.to_h
        subscription_id = context.delete(:subscription_id) || build_id
        channel = context.delete(:channel)
        stream = SUBSCRIPTION_PREFIX + subscription_id
        channel.stream_from(stream)

        data = {
          query_string: query.query_string,
          variables: query.provided_variables.to_json,
          context: @serializer.dump(context.to_h),
          operation_name: query.operation_name,
          events: events.map { |e| { topic: e.topic, fingerprint: e.fingerprint } }.to_json,
        }

        redis.multi do
          redis.sadd(CHANNEL_PREFIX + channel.params["channelId"], subscription_id)
          redis.mapped_hmset(SUBSCRIPTION_PREFIX + subscription_id, data)
          events.each do |event|
            redis.sadd(FINGERPRINTS_PREFIX + event.topic, event.fingerprint)
            redis.sadd(SUBSCRIPTIONS_PREFIX + event.fingerprint, subscription_id)
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
          :query_string, :variables, :context, :operation_name
        ).tap do |subscription|
          subscription[:context] = @serializer.load(subscription[:context])
          subscription[:variables] = JSON.parse(subscription[:variables])
          subscription[:operation_name] = nil if subscription[:operation_name].strip == ""
        end
      end

      def delete_subscription(subscription_id)
        events = redis.hget(SUBSCRIPTION_PREFIX + subscription_id, :events)
        events = events ? JSON.parse(events) : []
        events.each do |event|
          redis.srem(FINGERPRINTS_PREFIX + event["topic"], event["fingerprint"])
          redis.srem(SUBSCRIPTIONS_PREFIX + event["fingerprint"], subscription_id)
          redis.srem(EVENT_PREFIX + event["topic"], subscription_id) if config.handle_legacy_subscriptions
        end
        # Delete subscription itself
        redis.del(SUBSCRIPTION_PREFIX + subscription_id)
      end

      # The channel was closed, forget about it and its subscriptions
      def delete_channel_subscriptions(channel_id)
        redis.smembers(CHANNEL_PREFIX + channel_id).each do |subscription_id|
          delete_subscription(subscription_id)
        end
        redis.del(CHANNEL_PREFIX + channel_id)
      end

      private

      def anycable
        @anycable ||= ::AnyCable.broadcast_adapter
      end

      def prepare_payload(result)
        { result: result.to_h, more: true }.to_json
      end
    end
  end
end
# rubocop: enable Metrics/AbcSize, Metrics/LineLength, Metrics/MethodLength
