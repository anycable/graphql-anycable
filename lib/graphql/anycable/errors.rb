module GraphQL
  module AnyCable
    # This error is thrown when ActionCable channel wasn't provided to subscription implementation.
    # Typical cases:
    #  1. application developer forgot to pass ActionCable channel into context
    #  2. subscription query was sent via usual HTTP request, not websockets as intended
    class ChannelConfigurationError < ::RuntimeError
      def initialize(msg = nil)
        super(msg || <<~DEFAULT_MESSAGE)
          ActionCable channel wasn't provided in the context for GraphQL query execution!

          This can occur in the following cases:
           1. ActionCable channel instance wasn't passed into GraphQL execution context in the channel's execute method.
              See https://github.com/anycable/graphql-anycable#usage
           2. Subscription query was sent via usual HTTP request, not via WebSocket as intended
        DEFAULT_MESSAGE
      end
    end
  end
end
