# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Parsers::Tag do
  describe "#initialize" do
    it "creates tag from 4-character string" do
      tag = described_class.new("head")
      expect(tag.value).to eq("head")
    end

    it "pads short strings with spaces" do
      tag = described_class.new("a")
      expect(tag.value).to eq("a   ")

      tag = described_class.new("ab")
      expect(tag.value).to eq("ab  ")

      tag = described_class.new("abc")
      expect(tag.value).to eq("abc ")
    end

    it "truncates long strings to 4 characters" do
      tag = described_class.new("toolong")
      expect(tag.value).to eq("tool")
    end

    it "handles binary strings" do
      tag = described_class.new("OS/2")
      expect(tag.value).to eq("OS/2")
    end

    it "raises error for non-string input" do
      expect do
        described_class.new(123)
      end.to raise_error(Fontisan::Error, /Invalid tag/)
      expect do
        described_class.new(nil)
      end.to raise_error(Fontisan::Error, /Invalid tag/)
      expect do
        described_class.new([])
      end.to raise_error(Fontisan::Error, /Invalid tag/)
    end
  end

  describe "#to_s" do
    it "returns tag value as string" do
      tag = described_class.new("name")
      expect(tag.to_s).to eq("name")
    end

    it "returns padded value for short tags" do
      tag = described_class.new("a")
      expect(tag.to_s).to eq("a   ")
    end
  end

  describe "#==" do
    context "when comparing with another Tag" do
      it "returns true for equal tags" do
        tag1 = described_class.new("head")
        tag2 = described_class.new("head")

        expect(tag1).to eq(tag2)
      end

      it "returns false for different tags" do
        tag1 = described_class.new("head")
        tag2 = described_class.new("name")

        expect(tag1).not_to eq(tag2)
      end

      it "handles padding correctly" do
        tag1 = described_class.new("a")
        tag2 = described_class.new("a   ")

        expect(tag1).to eq(tag2)
      end
    end

    context "when comparing with String" do
      it "returns true for equal string" do
        tag = described_class.new("head")

        expect(tag).to eq("head")
      end

      it "returns false for different string" do
        tag = described_class.new("head")

        expect(tag).not_to eq("name")
      end

      it "handles padding when comparing with string" do
        tag = described_class.new("a")

        expect(tag).to eq("a")
        expect(tag).to eq("a   ")
      end
    end

    context "when comparing with other types" do
      it "returns false for non-Tag, non-String objects" do
        tag = described_class.new("head")

        expect(tag).not_to eq(123)
        expect(tag).not_to be_nil
        expect(tag).not_to eq([])
      end
    end
  end

  describe "#eql?" do
    it "behaves same as ==" do
      tag1 = described_class.new("head")
      tag2 = described_class.new("head")
      tag3 = described_class.new("name")

      expect(tag1.eql?(tag2)).to be true
      expect(tag1.eql?(tag3)).to be false
      expect(tag1.eql?("head")).to be true
    end
  end

  describe "#hash" do
    it "returns same hash for equal tags" do
      tag1 = described_class.new("head")
      tag2 = described_class.new("head")

      expect(tag1.hash).to eq(tag2.hash)
    end

    it "allows tags to be used as Hash keys" do
      hash = {}
      tag1 = described_class.new("head")
      tag2 = described_class.new("head")
      tag3 = described_class.new("name")

      hash[tag1] = "value1"
      hash[tag3] = "value2"

      expect(hash[tag2]).to eq("value1")
      expect(hash[tag3]).to eq("value2")
      expect(hash.size).to eq(2)
    end

    it "treats padded tags as equal in hashes" do
      hash = {}
      tag1 = described_class.new("a")
      tag2 = described_class.new("a   ")

      hash[tag1] = "value1"
      expect(hash[tag2]).to eq("value1")
      expect(hash.size).to eq(1)
    end
  end

  describe "#valid?" do
    it "returns true for exactly 4 characters" do
      tag = described_class.new("head")
      expect(tag.valid?).to be true
    end

    it "returns true for padded short strings" do
      tag = described_class.new("a")
      expect(tag.valid?).to be true # Becomes "a   "
    end

    it "returns true for truncated long strings" do
      tag = described_class.new("toolong")
      expect(tag.valid?).to be true # Becomes "tool"
    end

    it "returns true for empty string padded to 4 spaces" do
      tag = described_class.new("")
      expect(tag.valid?).to be true # Becomes "    "
    end
  end

  describe "common OpenType tags" do
    it "handles standard table tags" do
      tags = %w[head name post OS/2 cmap glyf loca maxp hhea hmtx]

      tags.each do |tag_str|
        tag = described_class.new(tag_str)
        expect(tag.valid?).to be true
        expect(tag.to_s).to eq(tag_str.ljust(4, " "))
      end
    end

    it "handles feature tags" do
      tags = %w[liga dlig smcp c2sc]

      tags.each do |tag_str|
        tag = described_class.new(tag_str)
        expect(tag.valid?).to be true
      end
    end

    it "handles script tags" do
      tags = %w[latn arab deva]

      tags.each do |tag_str|
        tag = described_class.new(tag_str)
        expect(tag.valid?).to be true
      end
    end
  end

  describe "edge cases" do
    it "handles special characters" do
      tag = described_class.new("OS/2")
      expect(tag.value).to eq("OS/2")
      expect(tag.valid?).to be true
    end

    it "preserves case" do
      tag = described_class.new("CaSe")
      expect(tag.value).to eq("CaSe")
    end

    it "handles numeric strings" do
      tag = described_class.new("1234")
      expect(tag.value).to eq("1234")
    end
  end
end
