# frozen_string_literal: true

RSpec.describe GraphQL::AnyCable::SubscriptionStores::Redis::Cleaner do
  subject(:cleaner) do
    described_class.new(
      redis_connector: ->(&block) { block.call($redis) },
      config: GraphQL::AnyCable.config
    )
  end

  let(:fingerprint) do
    ":productUpdated:/SomeSubscription/fBDZmJU1UGTorQWvOyUeaHVwUxJ3T9SEqnetj6SKGXc=/0/RBNvo1WzZ4oRRq0W9-hknpT7T8If536DEMBg9hyq_4o="
  end

  it "removes missing subscription ids from fingerprint sets" do
    $redis.sadd("graphql-subscriptions:#{fingerprint}", ["missing-subscription-id"])

    cleaner.clean_fingerprint_subscriptions

    expect($redis.smembers("graphql-subscriptions:#{fingerprint}")).to be_empty
  end

  it "removes topic fingerprints with no subscription set" do
    $redis.zadd("graphql-fingerprints::productUpdated:", 1, fingerprint)

    cleaner.clean_topic_fingerprints

    expect($redis.zrange("graphql-fingerprints::productUpdated:", 0, -1)).to be_empty
  end
end
