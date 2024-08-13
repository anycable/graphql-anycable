# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## Unreleased

## 1.3.0 - 2024-08-13

### Changed

- Redis subscriptions store configuration has been decoupled from AnyCable, so you can use any broadcasting adapter and configure Redis as you like. [@palkan] ([#44](https://github.com/anycable/graphql-anycable/pull/44))

## 1.2.0 - 2024-05-07

### Added

- Stats collection about subscriptions, channels, etc via `GraphQL::AnyCable.stats`. [@prog-supdex] ([#37](https://github.com/anycable/graphql-anycable/pull/37))

  See [Stats](https://github.com/anycable/graphql-anycable?tab=readme-ov-file#stats) section in README for details.

- Configuration option `redis_prefix` for namespacing Redis keys. [@prog-supdex] ([#36](https://github.com/anycable/graphql-anycable/pull/36))

### Changed

- Depend on `anycable-core` gem instead of `anycable`.

  This allows to avoid installing `grpc` gem when using alternate AnyCable broadcasting adapters (like HTTP).

  See https://github.com/anycable/graphql-anycable/issues/43 for details.

### Removed

- Handling of client-provided channel identifiers. **BREAKING CHANGE**

  Please make sure that you have changed your channel `disconnected` method to pass channel instance to GraphQL-AnyCable's `delete_channel_subscriptions` method.
  See [release notes for version 1.1.0](https://github.com/anycable/graphql-anycable/releases/tag/v1.1.0) for details.

- Handling of pre-1.0 subscriptions data.

  If you're still using version 0.5 or below, please upgrade to 1.0 or 1.1 first with `handle_legacy_subscriptions` setting enabled.
  See [release notes for version 1.0.0](https://github.com/anycable/graphql-anycable/releases/tag/v1.0.0) for details.

## 1.1.6 - 2023-08-03

### Fixed

- Fix empty operation name handling when using redis-client or redis.rb v5. [@ilyasgaraev] ([#34](https://github.com/anycable/graphql-anycable/pull/34))
- Fix deprecation warnings for redis.rb v4.8+ and support for redis.rb v5. [@smasry] ([#29](https://github.com/anycable/graphql-anycable/pull/29))

## 1.1.5 - 2022-10-26

- Fix that deprecation warning about `config.use_client_provided_uniq_id` again, so it can be issued outside of Rails. [@gsamokovarov] ([#27](https://github.com/anycable/graphql-anycable/pull/27))

## 1.1.4 - 2022-07-28

- Fix deprecation warning about using client-side channel ids shown even if deprecated functionality was disabled in application code (not via config file or environment variable). [@gsamokovarov] ([#26](https://github.com/anycable/graphql-anycable/pull/26))

  However, now deprecation warning won't be shown if graphql-anycable is used not in Ruby on Rails application.

## 1.1.3 - 2022-03-11

### Changed

- Allow using graphql-anycable with GraphQL-Ruby 2.x (it seem to be already compatible). [@Envek]

## 1.1.2 - 2022-03-11

### Fixed

- AnyCable 1.3.0 compatibility. [@palkan] [#21](https://github.com/anycable/graphql-anycable/pull/21)
- Redis.rb 5.0 compatibility. [@palkan] [#21](https://github.com/anycable/graphql-anycable/pull/21)

## 1.1.1 - 2021-12-06

### Fixed

- Handling of buggy istate values on unsubscribe (when `use_client_provided_uniq_id: false`). [@palkan] [#20](https://github.com/anycable/graphql-anycable/pull/20)
- A bug when `#unsubscribe` happens before `#execute`. [@palkan] [#20](https://github.com/anycable/graphql-anycable/pull/20)

## 1.1.0 - 2021-11-17

### Added

- Support for generating unique channel IDs server-side and storing them in the channel states.

  Currently, we rely on `params["channelId"]` to track subscriptions. This value is random when using `graphql-ruby` JS client, but is not guaranteed to be random in general.

  Now you can opt-in to use server-side IDs by specifying `use_client_provided_uniq_id: false` in YAML config or thru the `GRAPHQL_ANYCABLE_USE_CLIENT_PROVIDED_UNIQ_ID=false` env var.

  NOTE: Relying on client-side IDs is deprecated and will be removed in the future versions.

  You must also update your cleanup code in the `Channel#unsubscribed`:

```diff
-        channel_id = params.fetch("channelId")
-        MySchema.subscriptions.delete_channel_subscriptions(channel_id)
+        MySchema.subscriptions.delete_channel_subscriptions(self)
```

## 1.0.1 - 2021-04-16

### Added

 - Guard check for presence of ActionCable channel instance in the GraphQL execution context.

   This allows to detect wrong configuration (user forgot to pass channel into context) or wrong usage (subscription query was sent via HTTP request, not via WebSocket channel) of the library and provides clear error message to gem users.

## 1.0.0 - 2021-04-01

### Added

 - Support for [Subscriptions Broadcast](https://graphql-ruby.org/subscriptions/broadcast.html) feature in GraphQL-Ruby 1.11+. [@Envek] ([#15](https://github.com/anycable/graphql-anycable/pull/15))

### Changed

 - Subscription data storage format changed to support broadcasting feature (see [#15](https://github.com/anycable/graphql-anycable/pull/15))

### Removed

 - Drop support for GraphQL-Ruby before 1.11

 - Drop support for AnyCable before 1.0

 - Drop `:action_cable_stream` option from context: it is not used in reality.

   See [rmosolgo/graphql-ruby#3076](https://github.com/rmosolgo/graphql-ruby/pull/3076) for details

### Upgrading notes

 1. Change method of plugging in of this gem from `use GraphQL::Subscriptions::AnyCableSubscriptions` to `use GraphQL::AnyCable`:

    ```ruby
    use GraphQL::AnyCable
    ```

    If you need broadcasting, add `broadcast: true` option and ensure that [Interpreter mode](https://graphql-ruby.org/queries/interpreter.html) is enabled.

    ```ruby
    use GraphQL::Execution::Interpreter
    use GraphQL::Analysis::AST
    use GraphQL::AnyCable, broadcast: true, default_broadcastable: true
    ```

 2. Enable `handle_legacy_subscriptions` setting for seamless upgrade from previous versions:

    ```sh
    GRAPHQL_ANYCABLE_HANDLE_LEGACY_SUBSCRIPTIONS=true
    ```

    Disable or remove this setting when you sure that all clients has re-subscribed (e.g. after `subscription_expiration_seconds` has passed after upgrade) as it imposes small performance penalty.

## 0.5.0 - 2020-08-26

### Changed

 - Allow to plug in this gem by calling `use GraphQL::AnyCable` instead of `use GraphQL::Subscriptions::AnyCableSubscriptions`. [@Envek]
 - Rename `GraphQL::Anycable` constant to `GraphQL::AnyCable` for consistency with AnyCable itself. [@Envek]

## 0.4.2 - 2020-08-25

Technical release to test publishing via GitHub Actions.

## 0.4.1 - 2020-08-21

### Fixed

 - Deprecation warning for `Redis#exist` usage on Redis Ruby client 4.2+. Switch to `exists?` method and require Redis 4.2+ (see [#14](https://github.com/anycable/graphql-anycable/issues/14)). [@Envek]

## 0.4.0 - 2020-03-19

### Added

 - Ability to configure the gem via `configure` block, in addition to enironment variables and yaml files. [@gsamokovarov] ([#11](https://github.com/Envek/graphql-anycable/pull/11))
 - Ability to run Redis cleaning operations outside of Rake. [@gsamokovarov] ([#11](https://github.com/Envek/graphql-anycable/pull/11))
 - AnyCable 1.0 compatibility. [@bibendi], [@Envek] ([#10](https://github.com/Envek/graphql-anycable/pull/10))

## 0.3.3 - 2020-03-03

### Fixed

 - Redis command error on subscription query with multiple fields. [@Envek] ([#9](https://github.com/Envek/graphql-anycable/issues/9))

## 0.3.2 - 2020-03-02

### Added

 - Ability to skip some cleanup on restricted Redis instances (like Heroku). [@Envek] ([#8](https://github.com/Envek/graphql-anycable/issues/8))

## 0.3.1 - 2019-06-13

### Fixed

 - Empty operation name handling. [@FX-HAO] ([#3](https://github.com/Envek/graphql-anycable/pull/3))

## 0.3.0 - 2018-11-16

### Added

 - AnyCable 0.6 compatibility. [@Envek]

## 0.2.0 - 2018-09-17

### Added

 - Subscription expiration and rake task for stale subscriptions cleanup. [@Envek]

### 0.1.0 - 2018-08-26

Initial version: store subscriptions on redis, re-execute queries in sync. [@Envek]

[@prog-supdex]: https://github.com/prog-supdex "Igor Platonov"
[@ilyasgaraev]: https://github.com/ilyasgaraev "Ilyas Garaev"
[@smasry]: https://github.com/smasry "Samer Masry"
[@gsamokovarov]: https://github.com/gsamokovarov "Genadi Samokovarov"
[@bibendi]: https://github.com/bibendi "Misha Merkushin"
[@FX-HAO]: https://github.com/FX-HAO "Fuxin Hao"
[@Envek]: https://github.com/Envek "Andrey Novikov"
[@palkan]: https://github.com/palkan "Vladimir Dementyev"
