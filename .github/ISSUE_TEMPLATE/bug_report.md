---
name: Bug report
about: Create a report to help us improve graphql-anycable
title: ''
labels: ''
assignees: ''

---

**Describe the bug**
A clear and concise description of what the bug is.

**Versions**
ruby:
rails (or other framework):
graphql:
graphql-anycable:
anycable:

**GraphQL schema**
Provide relevant details. Are you using [subscription classes](https://graphql-ruby.org/subscriptions/subscription_classes.html) or not (graphql-ruby behavior differs there)?

```ruby
class Product < GraphQL::Schema::Object
  field :id, ID, null: false, hash_key: :id
  field :title, String, null: true, hash_key: :title
end

class SubscriptionType < GraphQL::Schema::Object
  field :product_created, Product, null: false
  field :product_updated, Product, null: false

  def product_created; end
  def product_updated; end
end

class ApplicationSchema < GraphQL::Schema
  subscription SubscriptionType
end
```

**GraphQL query**

How do you subscribe to subscriptions?

```graphql
subscription {
  productCreated { id title }
  productUpdated { id }
}
```

**Steps to reproduce**
Steps to reproduce the behavior

**Expected behavior**
A clear and concise description of what you expected to happen.

**Actual behavior**
What specifically went wrong?

**Additional context**
Add any other context about the problem here. Tracebacks, your thoughts. anything that may be useful.
