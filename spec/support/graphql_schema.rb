# frozen_string_literal: true

class Product < GraphQL::Schema::Object
  field :id, ID, null: false, hash_key: :id
  field :title, String, null: true, hash_key: :title
end

class SubscriptionType < GraphQL::Schema::Object
  field :product_created, Product, null: false, resolver_method: :default_resolver
  field :product_updated, Product, null: false, resolver_method: :default_resolver

  def default_resolver
    return object if context.query.subscription_update?

    context.skip
  end
end

class AnycableSchema < GraphQL::Schema
  use GraphQL::AnyCable

  if TESTING_GRAPHQL_RUBY_INTERPRETER
    use GraphQL::Execution::Interpreter
    use GraphQL::Analysis::AST
  end

  subscription SubscriptionType
end
