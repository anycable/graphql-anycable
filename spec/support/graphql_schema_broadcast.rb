# frozen_string_literal: true

return unless TESTING_GRAPHQL_RUBY_INTERPRETER # Broadcast requires interpreter

class Post < GraphQL::Schema::Object
  field :id, ID, null: false, broadcastable: true
  field :title, String, null: true
  field :actions, [String], null: false, broadcastable: false
end

class PostCreated < GraphQL::Schema::Subscription
  payload_type Post
end

class BroadcastSubscriptionType < GraphQL::Schema::Object
  field :post_created, subscription: PostCreated
end

class BroadcastSchema < GraphQL::Schema
  use GraphQL::Execution::Interpreter
  use GraphQL::Analysis::AST
  use GraphQL::AnyCable, broadcast: true, default_broadcastable: true

  subscription BroadcastSubscriptionType
end
