# frozen_string_literal: true

POSTS = [
  { id: "a", title: "GraphQL is good?", actions: %w[yes no] },
  { id: "b", title: "Is there life after GraphQL?", actions: %w[no still-no] }
].freeze

class Product < GraphQL::Schema::Object
  field :id, ID, null: false, hash_key: :id
  field :title, String, null: true, hash_key: :title
end

class Post < GraphQL::Schema::Object
  field :id, ID, null: false, broadcastable: true
  field :title, String, null: true
  field :actions, [String], null: false, broadcastable: false
end

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

class SubscriptionType < GraphQL::Schema::Object
  field :product_created, Product, null: false, resolver_method: :default_resolver
  field :product_updated, Product, null: false, resolver_method: :default_resolver
  field :post_updated, subscription: PostUpdated

  def default_resolver
    return object if context.query.subscription_update?

    context.skip
  end
end

class BaseObject < GraphQL::Schema::Object
  field :class_type, String, null: false

  def class_type
    object.class.name.camelize(:lower)
  end
end

class StrategyType < BaseObject
  field :id, ID, null: false
end

class Strategy < Hash; end

class QueryType < GraphQL::Schema::Object
  field :strategy, StrategyType

  def strategy
    Strategy.new.tap do |h|
      h[:id] = 2134
      h[:class_type] = "strategy"
    end
  end
end

class AnycableSchema < GraphQL::Schema
  use GraphQL::AnyCable

  query QueryType
  subscription SubscriptionType
end

module Broadcastable
  class PostCreated < GraphQL::Schema::Subscription
    payload_type Post
  end


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

  class SubscriptionType < GraphQL::Schema::Object
    field :post_created, subscription: PostCreated
    field :post_updated, subscription: PostUpdated
  end
end

class BroadcastSchema < GraphQL::Schema
  use GraphQL::AnyCable, broadcast: true, default_broadcastable: true

  subscription Broadcastable::SubscriptionType
  query QueryType
end
