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

POSTS = [
  { id: "a", title: "GraphQL is good?", actions: %w[yes no] },
  { id: "b", title: "Is there life after GraphQL?", actions: %w[no still-no] }
].freeze

class PostUpdated < GraphQL::Schema::Subscription
  argument :id, ID, required: true

  field :post, Post, null: false

  def subscribe(id:)
    {post: POSTS.find { |post| post[:id] == id }}
  end

  def update(*)
    {post: object}
  end
end

class BroadcastSubscriptionType < GraphQL::Schema::Object
  field :post_created, subscription: PostCreated
  field :post_updated, subscription: PostUpdated
end

class BroadcastSchema < GraphQL::Schema
  use GraphQL::Execution::Interpreter
  use GraphQL::Analysis::AST
  use GraphQL::AnyCable, broadcast: true, default_broadcastable: true

  subscription BroadcastSubscriptionType
end
