# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## Unreleased

### Removed

 - Drop support for GraphQL-Ruby before 1.11

 - Drop support for AnyCable before 1.0

 - Drop `:action_cable_stream` option from context: it is not used in reality.

   See [rmosolgo/graphql-ruby#3076](https://github.com/rmosolgo/graphql-ruby/pull/3076) for details

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

[@gsamokovarov]: https://github.com/gsamokovarov "Genadi Samokovarov"
[@bibendi]: https://github.com/bibendi "Misha Merkushin"
[@FX-HAO]: https://github.com/FX-HAO "Fuxin Hao"
[@Envek]: https://github.com/Envek "Andrey Novikov"
