# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Export::TableSerializer do
  it "serializes the CFF mixed summary with its binary payload" do
    table = Struct.new(:data) do
      def to_binary_s
        data
      end
    end.new("cff".b)

    result = described_class.new.serialize(table, "CFF")

    expect(result[:parsed]).to be(true)
    expect(JSON.parse(result[:fields])).to eq(
      "type" => "CFF",
      "note" => "CharString data stored as binary",
    )
    expect(result[:data]).to eq("636666")
  end
end
