# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"

RSpec.describe Fontisan::GlyphLimitExceededError do
  it "stores actual, limit, and format" do
    error = described_class.new(actual: 100_000, limit: 65_535, format: :ttf)
    expect(error.actual).to eq(100_000)
    expect(error.limit).to eq(65_535)
    expect(error.format).to eq(:ttf)
  end

  it "is a subclass of Fontisan::Error" do
    expect(described_class.new(actual: 1, limit: 0, format: :ttf))
      .to be_a(Fontisan::Error)
  end

  it "mentions the actual count and format in the message" do
    error = described_class.new(actual: 70_000, limit: 65_535, format: :ttf)
    expect(error.message).to include("70000")
    expect(error.message).to include("TTF")
  end
end
