# frozen_string_literal: true

require "spec_helper"
require "fontisan/font_builder"

RSpec.describe Fontisan::FontBuilder::Main do
  describe "#initialize" do
    it "defaults to TrueType format" do
      expect(described_class.new.format).to eq(:ttf)
    end

    it "accepts an explicit format" do
      expect(described_class.new(format: :otf).format).to eq(:otf)
    end

    it "starts with an empty FontModel" do
      writer = described_class.new
      expect(writer.model).to be_a(Fontisan::FontBuilder::FontModel)
      expect(writer.model.cmap).to eq({})
    end
  end

  describe "#set_cmap" do
    it "records the unicode → gid map" do
      writer = described_class.new
      writer.set_cmap(0x41 => 1, 0x42 => 2)
      expect(writer.model.cmap).to eq(0x41 => 1, 0x42 => 2)
    end

    it "creates empty glyph entries for each gid" do
      writer = described_class.new
      writer.set_cmap(0x41 => 1)
      expect(writer.model.glyphs[1]).to be_a(Fontisan::FontBuilder::GlyphEntry)
    end

    it "merges with an existing cmap rather than replacing" do
      writer = described_class.new
      writer.set_cmap(0x41 => 1)
      writer.set_cmap(0x42 => 2)
      expect(writer.model.cmap).to eq(0x41 => 1, 0x42 => 2)
    end
  end

  describe "#add_glyph" do
    it "stores the outline + metrics at the given gid" do
      writer = described_class.new
      outline = Fontisan::FontBuilder::Outline.new
      metrics = Fontisan::FontBuilder::Metrics.new(advance_width: 600)
      writer.add_glyph(1, outline: outline, metrics: metrics)
      expect(writer.model.glyphs[1].outline).to eq(outline)
      expect(writer.model.glyphs[1].metrics.advance_width).to eq(600)
    end
  end

  describe "#set_name_records" do
    it "stores the records" do
      writer = described_class.new
      record = Fontisan::FontBuilder::NameRecord.new(name_id: 1, string: "Test Font")
      writer.set_name_records([record])
      expect(writer.model.names).to eq([record])
    end

    it "is immune to caller-side mutation after set (defensive copy)" do
      writer = described_class.new
      records = [Fontisan::FontBuilder::NameRecord.new(name_id: 1, string: "Original")]
      writer.set_name_records(records)
      records.clear
      expect(writer.model.names.length).to eq(1)
    end
  end
end
