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

      SUBSCRIPTION_PREFIX  = "graphql-subscription:"  # HASH: Stores subscription data: query, context, …
      FINGERPRINTS_PREFIX  = "graphql-fingerprints:"  # ZSET: To get fingerprints by topic
      SUBSCRIPTIONS_PREFIX = "graphql-subscriptions:" # SET:  To get subscriptions by fingerprint
      CHANNEL_PREFIX       = "graphql-channel:"       # SET:  Auxiliary structure for whole channel's subscriptions cleanup
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

        fingerprints = redis.zrange(FINGERPRINTS_PREFIX + event.topic, 0, -1)
        return if fingerprints.empty?

        fingerprint_subscription_ids = Hash[fingerprints.zip(
          redis.pipelined do
            fingerprints.map do |fingerprint|
              redis.smembers(SUBSCRIPTIONS_PREFIX + fingerprint)
            end
          end
        )]

        fingerprint_subscription_ids.each do |fingerprint, subscription_ids|
          execute_grouped(fingerprint, subscription_ids, event, object)
        end

        # Call to +trigger+ returns this. Convenient for playing in console
        Hash[fingerprint_subscription_ids.map { |k,v| [k, v.size] }]
      end

      def execute_grouped(fingerprint, subscription_ids, event, object)
        return if subscription_ids.empty?

        # The fingerprint has told us that this response should be shared by all subscribers,
        # so just run it once, then deliver the result to every subscriber
        result = execute_update(subscription_ids.first, event, object)
        return unless result

        # Having calculated the result _once_, send the same payload to all subscribers
        deliver(SUBSCRIPTIONS_PREFIX + fingerprint, result)
      end

      # For migration from pre-1.0 graphql-anycable gem
      def execute_legacy(event, object)
        redis.smembers(EVENT_PREFIX + event.topic).each do |subscription_id|
          next unless redis.exists?(SUBSCRIPTION_PREFIX + subscription_id)
          result = execute_update(subscription_id, event, object)
          next unless result

          deliver(SUBSCRIPTION_PREFIX + subscription_id, result)
        end
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
        payload = { result: result.to_h, more: true }.to_json
        anycable.broadcast(stream_key, payload)
      end

      # Save query to "storage" (in redis)
      def write_subscription(query, events)
        context = query.context.to_h
        subscription_id = context.delete(:subscription_id) || build_id
        channel = context.delete(:channel)

        events.each do |event|
          channel.stream_from(SUBSCRIPTIONS_PREFIX + event.fingerprint)
        end

        data = {
          query_string: query.query_string,
          variables: query.provided_variables.to_json,
          context: @serializer.dump(context.to_h),
          operation_name: query.operation_name,
          events: events.map { |e| [e.topic, e.fingerprint] }.to_h.to_json,
        }

        redis.multi do
          redis.sadd(CHANNEL_PREFIX + channel.params["channelId"], subscription_id)
          redis.mapped_hmset(SUBSCRIPTION_PREFIX + subscription_id, data)
          events.each do |event|
            redis.zincrby(FINGERPRINTS_PREFIX + event.topic, 1, event.fingerprint)
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
        events = events ? JSON.parse(events) : {}
        fingerprint_subscriptions = {}
        redis.pipelined do
          events.each do |topic, fingerprint|
            redis.srem(SUBSCRIPTIONS_PREFIX + fingerprint, subscription_id)
            score = redis.zincrby(FINGERPRINTS_PREFIX + topic, -1, fingerprint)
            fingerprint_subscriptions[FINGERPRINTS_PREFIX + topic] = score
          end
          # Delete subscription itself
          redis.del(SUBSCRIPTION_PREFIX + subscription_id)
        end
        # Clean up fingerprints that doesn't have any subscriptions left
        redis.pipelined do
          fingerprint_subscriptions.each do |key, score|
            redis.zremrangebyscore(key, '-inf', '0') if score.value.zero?
          end
        end
        delete_legacy_subscription(subscription_id)
      end

      def delete_legacy_subscription(subscription_id)
        return unless config.handle_legacy_subscriptions

        events = redis.smembers(SUBSCRIPTION_EVENTS_PREFIX + subscription_id)
        redis.pipelined do
          events.each do |event_topic|
            redis.srem(EVENT_PREFIX + event_topic, subscription_id)
          end
          redis.del(SUBSCRIPTION_EVENTS_PREFIX + subscription_id)
        end
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
    end
  end
end
# rubocop: enable Metrics/AbcSize, Metrics/LineLength, Metrics/MethodLength
