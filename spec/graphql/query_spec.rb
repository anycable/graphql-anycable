# frozen_string_literal: true

RSpec.describe "Query without subscriptions" do
  subject { BroadcastSchema.execute(query: query) }

  let(:query) do
    <<~GRAPHQL.strip
      query SomeQuery { strategy { id classType } }
    GRAPHQL
  end

  it "works" do
    expect(subject["data"]).to eq(
      "strategy" => {
        "id" => "2134",
        "classType" => "strategy",
      },
    )
  end
end
