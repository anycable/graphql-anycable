# frozen_string_literal: true

RSpec.describe GraphQL::AnyCable::DeliveryAdapter do
  describe ".lookup" do
    context "when config.delivery_method is valid" do
      around do |ex|
        old_value = GraphQL::AnyCable.config.delivery_method
        GraphQL::AnyCable.config.delivery_method = :inline

        ex.run

        GraphQL::AnyCable.config.delivery_method = old_value
      end

      it "returns InlineAdapter" do
        expect(GraphQL::Adapters::InlineAdapter).to receive(:new).with(executor_object: "object")

        described_class.lookup(executor_object: "object")
      end
    end

    context "when config.delivery_method is invalid" do
      around do |ex|
        old_value = GraphQL::AnyCable.config.delivery_method
        GraphQL::AnyCable.config.delivery_method = :unknown_adapter

        ex.run

        GraphQL::AnyCable.config.delivery_method = old_value
      end

      it "raises an error" do
        expect { described_class.lookup(executor_object: "object") }.to raise_error(
          NameError,
          /Delivery adapter :unknown_adapter haven't been found/,
        )
      end
    end
  end
end
