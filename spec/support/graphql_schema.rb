# frozen_string_literal: true

class Product < GraphQL::Schema::Object
  field :id, ID, null: false, hash_key: :id
  field :title, String, null: true, hash_key: :title
end

class SubscriptionType < GraphQL::Schema::Object
  field :product_updated, Product, null: false

  # See https://github.com/rmosolgo/graphql-ruby/issues/1567
  def product_updated; end
end

class AnycableSchema < GraphQL::Schema
  use GraphQL::Subscriptions::AnyCableSubscriptions

  subscription SubscriptionType
end
