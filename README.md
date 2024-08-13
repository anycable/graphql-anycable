# GraphQL subscriptions for AnyCable

A (mostly) drop-in replacement for default ActionCable subscriptions adapter shipped with [graphql gem] but works with [AnyCable]!

[![Gem Version](https://badge.fury.io/rb/graphql-anycable.svg)](https://badge.fury.io/rb/graphql-anycable)
[![Tests](https://github.com/anycable/graphql-anycable/actions/workflows/test.yml/badge.svg)](https://github.com/anycable/graphql-anycable/actions/workflows/test.yml)

<a href="https://evilmartians.com/?utm_source=graphql-anycable&utm_campaign=project_page">
<img src="https://evilmartians.com/badges/sponsored-by-evil-martians.svg" alt="Sponsored by Evil Martians" width="236" height="54">
</a>

## Why?

AnyCable is fast because it does not execute any Ruby code. But default subscription implementation shipped with [graphql gem] requires to do exactly that: re-evaluate GraphQL queries in Action Cable process. AnyCable doesn't support this (it's possible but hard to implement).

See https://github.com/anycable/anycable-rails/issues/40 for more details and discussion.

## Differences

- Subscription information is stored in a Redis database. By default, we use AnyCable Redis configuration. Expiration or data cleanup should be configured separately (see below).
- GraphQL queries for all subscriptions are re-executed in the process that triggers event (it may be web server, async jobs, rake tasks or whatever)

## Compatibility

- Works with Action Cable (e.g., in development/test)
- Works without Rails (e.g., via [LiteCable][])

## Installation

Add this line to your application's Gemfile:

```ruby
gem "graphql-anycable", "~> 1.0"
```

And then execute:

```sh
bundle install
```

## Usage

 1. Plug it into the schema (replace the Action Cable adapter if you have one):

    ```ruby
    class MySchema < GraphQL::Schema
      use GraphQL::AnyCable, broadcast: true

      subscription SubscriptionType
    end
    ```

 2. Execute a query within an Action Cable/LiteCable channel.

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
        MySchema.subscriptions.delete_channel_subscriptions(self)
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

 4. (Optional) When using other AnyCable broadcasting adapters than Redis, you MUST configure Redis for graphql-anycable yourself:

    ```ruby
    GraphQL::AnyCable.redis = Redis.new(url: ENV["REDIS_URL"])

    # you can also use a Proc (e.g., if you want to use a connection pool)
    redis_pool = ConnectionPool.new(size: 10) { Redis.new(url: ENV["REDIS_URL"]) }

    GraphQL::AnyCable.redis = ->(&block) { redis_pool.with { |conn| block.call(conn) } }
    ```

## Broadcasting

By default, graphql-anycable evaluates queries and transmits results for every subscription client individually. Of course, it is a waste of resources if you have hundreds or thousands clients subscribed to the same data (and has huge negative impact on performance).

Thankfully, GraphQL-Ruby has added [Subscriptions Broadcast](https://graphql-ruby.org/subscriptions/broadcast.html) feature that allows to group exact same subscriptions, execute them and transmit results only once.

To enable this feature, pass the `broadcast` option set to `true` to graphql-anycable.

By default all fields are marked as _not safe for broadcasting_. If a subscription has at least one non-broadcastable field in its query, GraphQL-Ruby will execute every subscription for every client independently. If you sure that all your fields are safe to be broadcasted, you can pass `default_broadcastable` option set to `true` (but be aware that it can have security impllications!)

```ruby
class MySchema < GraphQL::Schema
  use GraphQL::AnyCable, broadcast: true, default_broadcastable: true

  subscription SubscriptionType
end
```

See GraphQL-Ruby [broadcasting docs](https://graphql-ruby.org/subscriptions/broadcast.html) for more details.

## Operations

To avoid filling Redis storage with stale subscription data:

 1. Set `subscription_expiration_seconds` setting to number of seconds (e.g. `604800` for 1 week). See [configuration](#configuration) section below for details.

 2. Execute `rake graphql:anycable:clean` once in a while to clean up stale subscription data.

    Heroku users should set up `use_redis_object_on_cleanup` setting to `false` due to [limitations in Heroku Redis](https://devcenter.heroku.com/articles/heroku-redis#connection-permissions).

## Configuration

GraphQL-AnyCable uses [anyway_config] to configure itself. There are several possibilities to configure this gem:

 1. Environment variables:

    ```.env
    GRAPHQL_ANYCABLE_SUBSCRIPTION_EXPIRATION_SECONDS=604800
    GRAPHQL_ANYCABLE_USE_REDIS_OBJECT_ON_CLEANUP=true
    GRAPHQL_ANYCABLE_REDIS_PREFIX=graphql
    ```

 2. YAML configuration files (note that this is `config/graphql_anycable.yml`, *not* `config/anycable.yml`):

    ```yaml
    # config/graphql_anycable.yml
    production:
      subscription_expiration_seconds: 300 # 5 minutes
      use_redis_object_on_cleanup: false # For restricted redis installations
      redis_prefix: graphql # You can configure redis_prefix for anycable-graphql subscription prefixes. Default value "graphql"
    ```

 3. Configuration from your application code:

    ```ruby
    GraphQL::AnyCable.configure do |config|
      config.subscription_expiration_seconds = 3600 # 1 hour
      config.redis_prefix = "graphql" # on our side, we add `-` ourselves after the redis_prefix
    end
    ```

And any other way provided by [anyway_config]. Check its documentation!

## Emergency actions

In situations when you don't set `subscription_expiration_seconds`, have a lot of inactive subscriptions, and `GraphQL::AnyCable::Cleaner` does`t help in that,
you can do the following actions for clearing subscriptions

1. Set `config.subscription_expiration_seconds`. After that, the new subscriptions will have `TTL`

2. Run the script

```ruby
config = GraphQL::AnyCable.config

GraphQL::AnyCable.with_redis do |redis|
  # do it for subscriptions
  redis.scan_each("graphql-subscription:*") do |key|
    redis.expire(key, config.subscription_expiration_seconds) if redis.ttl(key) < 0
    # or you can just remove it immediately
    # redis.del(key) if redis.ttl(key) < 0
  end

  # do it for channels
  redis.scan_each("graphql-channel:*") do |key|
    redis.expire(key, config.subscription_expiration_seconds) if redis.ttl(key) < 0
    # or you can just remove it immediately
    # redis.del(key) if redis.ttl(key) < 0
  end
end
```

Or you can change the `redis_prefix` in the `configuration` and then remove all records with the old_prefix. For instance:

1. Change the `redis_prefix`. The default `redis_prefix` is `graphql`.

2. Run the ruby script, which remove all records with `old prefix`:

```ruby
GraphQL::AnyCable.with_redis do |redis|
  redis.scan_each("graphql-*") do |key|
    redis.del(key)
  end
end
```

## Data model

As in AnyCable there is no place to store subscription data in-memory, it should be persisted somewhere to be retrieved on `GraphQLSchema.subscriptions.trigger` and sent to subscribed clients. `graphql-anycable` uses the same Redis database as AnyCable itself.

 1. Grouped event subscriptions: `graphql-fingerprints:#{event.topic}` sorted set. Used to find all subscriptions on `GraphQLSchema.subscriptions.trigger`.

    ```sh
    ZREVRANGE graphql-fingerprints:1:myStats: 0 -1
    => 1:myStats:/MyStats/fBDZmJU1UGTorQWvOyUeaHVwUxJ3T9SEqnetj6SKGXc=/0/RBNvo1WzZ4oRRq0W9-hknpT7T8If536DEMBg9hyq_4o=
    ```

 2. Event subscriptions: `graphql-subscriptions:#{event.fingerptint}` set containing identifiers for all subscriptions for given operation with certain context and arguments (serialized in _topic_). Fingerprints are already scoped by topic.

    ```sh
    SMEMBERS graphql-subscriptions:1:myStats:/MyStats/fBDZmJU1UGTorQWvOyUeaHVwUxJ3T9SEqnetj6SKGXc=/0/RBNvo1WzZ4oRRq0W9-hknpT7T8If536DEMBg9hyq_4o=
    => 52ee8d65-275e-4d22-94af-313129116388
    ```

 3. Subscription data: `graphql-subscription:#{subscription_id}` hash contains everything required to evaluate subscription on trigger and create data for client.

    ```sh
    HGETALL graphql-subscription:52ee8d65-275e-4d22-94af-313129116388
    => {
      context:        '{"user_id":1,"user":{"__gid__":"Z2lkOi8vZWJheS1tYWcyL1VzZXIvMQ"}}',
      variables:      '{}',
      operation_name: 'MyStats'
      query_string:   'subscription MyStats { myStatsUpdated { completed total processed __typename } }',
    }
    ```

 4. Channel subscriptions: `graphql-channel:#{subscription_id}` set containing identifiers for subscriptions created in ActionCable channel to delete them on client disconnect.

    ```sh
    SMEMBERS graphql-channel:17420c6ed9e
    => 52ee8d65-275e-4d22-94af-313129116388
    ```

## Stats

You can grab Redis subscription statistics by calling:

```ruby
GraphQL::AnyCable.stats
```

It will return a total of the amount of the key with the following prefixes:

```txt
graphql-subscription
graphql-fingerprints
graphql-subscriptions
graphql-channel
```

The response will look like this:

```json
  {
    "total": {
      "subscription":22646,
      "fingerprints":3200,
      "subscriptions":20101,
      "channel": 4900
    }
  }
```

You can also grab the number of subscribers grouped by subscriptions:

```ruby
GraphQL::AnyCable.stats(include_subscriptions: true)
```

It will return the response that contains `subscriptions`:

```json
  {
    "total": {
      "subscription":22646,
      "fingerprints":3200,
      "subscriptions":20101,
      "channel": 4900
    },
    "subscriptions": {
      "productCreated": 11323,
      "productUpdated": 11323
    }
  }
```

Also, you can set another `scan_count`, if needed. The default value is 1_000:

```ruby
GraphQL::AnyCable.stats(scan_count: 100)
```

We can set statistics data to [Yabeda][] for tracking amount of subscriptions:

```ruby
# config/initializers/metrics.rb
Yabeda.configure do
  group :graphql_anycable_statistics do
    gauge :subscriptions_count,  comment: "Number of graphql-anycable subscriptions"
  end
end
```

```ruby
# in your app
statistics = GraphQL::AnyCable.stats[:total]

statistics.each do |key , value|
  Yabeda.graphql_anycable_statistics.subscriptions_count.set({name: key}, value)
end
```

Or you can use `collect`:

```ruby
# config/initializers/metrics.rb
Yabeda.configure do
  group :graphql_anycable_statistics do
    gauge :subscriptions_count,  comment: "Number of graphql-anycable subscriptions"
  end

  collect do
    statistics = GraphQL::AnyCable.stats[:total]

    statistics.each do |redis_prefix, value|
      graphql_anycable_statistics.subscriptions_count.set({name: redis_prefix}, value)
    end
  end
end
```

## Testing applications which use `graphql-anycable`

You can pass custom redis-server URL to AnyCable using ENV variable.

```bash
REDIS_URL=redis://localhost:6379/5 bundle exec rspec
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

### Releasing new versions

1. Bump version number in `lib/graphql/anycable/version.rb`

   In case of pre-releases keep in mind [rubygems/rubygems#3086](https://github.com/rubygems/rubygems/issues/3086) and check version with command like `Gem::Version.new(AfterCommitEverywhere::VERSION).to_s`

2. Fill `CHANGELOG.md` with missing changes, add header with version and date.

3. Make a commit:

   ```sh
   git add lib/graphql/anycable/version.rb CHANGELOG.md
   version=$(ruby -r ./lib/graphql/anycable/version.rb -e "puts Gem::Version.new(GraphQL::AnyCable::VERSION)")
   git commit --message="${version}: " --edit
   ```

4. Create annotated tag:

   ```sh
   git tag v${version} --annotate --message="${version}: " --edit --sign
   ```

5. Fill version name into subject line and (optionally) some description (list of changes will be taken from `CHANGELOG.md` and appended automatically)

6. Push it:

   ```sh
   git push --follow-tags
   ```

7. GitHub Actions will create a new release, build and push gem into [rubygems.org](https://rubygems.org)! You're done!

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Envek/graphql-anycable.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

[graphql gem]: https://github.com/rmosolgo/graphql-ruby "Ruby implementation of GraphQL"
[AnyCable]: https://github.com/anycable/anycable "Polyglot replacement for Ruby WebSocket servers with Action Cable protocol"
[LiteCable]: https://github.com/palkan/litecable "Lightweight Action Cable implementation (Rails-free)"
[anyway_config]: https://github.com/palkan/anyway_config "Ruby libraries and applications configuration on steroids!"
[Yabeda]: https://github.com/yabeda-rb/yabeda "Extendable solution for easy setup of monitoring in your Ruby apps"
