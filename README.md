# GraphQL subscriptions for AnyCable

A (mostly) drop-in replacement for default ActionCable subscriptions adapter shipped with [graphql gem] but works with [AnyCable]!

**IMPORTANT**: This gem is still in _proof of concept_ stage. It is not yet tested in production and everything may change without any notice. You have warned. 

[![Gem Version](https://badge.fury.io/rb/graphql-anycable.svg)](https://badge.fury.io/rb/graphql-anycable)

<a href="https://evilmartians.com/?utm_source=graphql-anycable&utm_campaign=project_page">
<img src="https://evilmartians.com/badges/sponsored-by-evil-martians.svg" alt="Sponsored by Evil Martians" width="236" height="54">
</a>

## Why?

AnyCable is fast because it does not execute any Ruby code. But default subscription implementation shipped with [graphql gem] requires to do exactly that: re-evaluate GraphQL queries in ActionCable process. AnyCable doesn't support this (it's possible but hard to implement).

See https://github.com/anycable/anycable-rails/issues/40 for more details and discussion.

## Differences

 - Subscription information is stored in Redis database configured to be used by AnyCable. No expiration or data cleanup yet.
 - GraphQL queries for all subscriptions are re-executed in the process that triggers event (it may be web server, async jobs, rake tasks or whatever)

## Compatibility

 - Should work with ActionCable in development
 - Should work without Rails via [LiteCable] 

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'graphql-anycable'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install graphql-anycable

## Usage

 1. Plug it into the schema (replace from ActionCable adapter if you have one):
 
    ```ruby
    class MySchema < GraphQL::Schema
      use GraphQL::Subscriptions::AnyCableSubscriptions
    
      subscription SubscriptionType
    end
    ```
 
 2. Execute query in ActionCable/LiteCable channel.
 
    ```ruby
    class GraphqlChannel < ApplicationCable::Channel
      def execute(data)
        result = 
          MySchema.execute(
            query: data["query"],
            context: context,
            variables: Hash(data["variables"]),
            operation_name: data["operationName"],
          )

        transmit(
          result: result.subscription? ? { data: nil } : result.to_h,
          more: result.subscription?,
        )
      end
    
      def unsubscribed
        channel_id = params.fetch("channelId")
        MySchema.subscriptions.delete_channel_subscriptions(channel_id)
      end
    
      private

      def context
        {
          account_id: account&.id,
          channel: self,
        }
      end
    end
    ```
 
    Make sure that you're passing channel instance as `channel` key to the context. 
 
 3. Trigger events as usual:
 
    ```ruby
    MySchema.subscriptions.trigger(:product_updated, {}, Product.first!, scope: account.id)
    ```

## Operations

To avoid filling Redis storage with stale subscription data:

 1. Set `GRAPHQL_ANYCABLE_SUBSCRIPTION_EXPIRATION_SECONDS` environment variable to number of seconds (e.g. `604800` for 1 week). See [anyway_config] documentation to other ways of configuring this gem.
 2. Execute `rake graphql:anycable:clean_expired_subscriptions` once in a while to clean up stale subscription data

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Envek/graphql-anycable.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

[graphql gem]: https://github.com/rmosolgo/graphql-ruby "Ruby implementation of GraphQL"
[AnyCable]: https://github.com/anycable/anycable "Polyglot replacement for Ruby WebSocket servers with Action Cable protocol"
[LiteCable]: https://github.com/palkan/litecable "Lightweight Action Cable implementation (Rails-free)"
[anyway_config]: https://github.com/palkan/anyway_config "Ruby libraries and applications configuration on steroids!"
