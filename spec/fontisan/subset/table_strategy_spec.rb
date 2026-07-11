# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Subset::TableStrategy do
  describe ".for" do
    it "resolves known tags to their strategy class" do
      expect(described_class.for("maxp")).to eq(described_class::Maxp)
      expect(described_class.for("hhea")).to eq(described_class::Hhea)
      expect(described_class.for("hmtx")).to eq(described_class::Hmtx)
      expect(described_class.for("loca")).to eq(described_class::Loca)
      expect(described_class.for("glyf")).to eq(described_class::Glyf)
      expect(described_class.for("cmap")).to eq(described_class::Cmap)
      expect(described_class.for("post")).to eq(described_class::Post)
      expect(described_class.for("name")).to eq(described_class::Name)
      expect(described_class.for("head")).to eq(described_class::Head)
      expect(described_class.for("OS/2")).to eq(described_class::Os2)
      expect(described_class.for("CBDT")).to eq(described_class::Cbdt)
      expect(described_class.for("CBLC")).to eq(described_class::Cblc)
      expect(described_class.for("CFF2")).to eq(described_class::Cff2)
    end

    it "falls back to PassThrough for unknown tags" do
      expect(described_class.for("kern"))
        .to eq(described_class::PassThrough)
      expect(described_class.for("DSIG"))
        .to eq(described_class::PassThrough)
    end
  end

  describe "REGISTRY" do
    it "is frozen so callers cannot mutate it at runtime" do
      expect(described_class::REGISTRY).to be_frozen
    end

    it "includes every tag covered by the default web profile" do
      required = %w[maxp hhea hmtx loca glyf cmap post name head OS/2
                    CBDT CBLC]
      required.each do |tag|
        expect(described_class::REGISTRY).to have_key(tag),
                                             "missing strategy for #{tag}"
      end
    end
  end

  describe "strategy interface" do
    it "every registered strategy class responds to .call" do
      described_class::REGISTRY.each_value do |sym|
        klass = described_class.const_get(sym)
        expect(klass).to respond_to(:call),
                         "#{sym} does not respond to .call"
      end
    end

    it "PassThrough responds to .call" do
      expect(described_class::PassThrough).to respond_to(:call)
    end
  end
end
