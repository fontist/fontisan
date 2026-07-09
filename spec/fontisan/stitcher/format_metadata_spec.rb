# frozen_string_literal: true

require "spec_helper"
require "fontisan/stitcher"

RSpec.describe Fontisan::Stitcher::FormatMetadata do
  describe ".resolve" do
    it "maps :ttf to TtfCompiler + :ttc + .ttf" do
      meta = described_class.resolve(:ttf)
      expect(meta.name).to eq(:ttf)
      expect(meta.compiler_class).to eq(Fontisan::Ufo::Compile::TtfCompiler)
      expect(meta.collection_format).to eq(:ttc)
      expect(meta.extension).to eq(".ttf")
    end

    it "maps :otf to OtfCompiler + :otc + .otf" do
      meta = described_class.resolve(:otf)
      expect(meta.name).to eq(:otf)
      expect(meta.compiler_class).to eq(Fontisan::Ufo::Compile::OtfCompiler)
      expect(meta.collection_format).to eq(:otc)
      expect(meta.extension).to eq(".otf")
    end

    it "maps :otf2 to Otf2Compiler + :otc + .otf" do
      meta = described_class.resolve(:otf2)
      expect(meta.name).to eq(:otf2)
      expect(meta.compiler_class).to eq(Fontisan::Ufo::Compile::Otf2Compiler)
      expect(meta.collection_format).to eq(:otc)
      expect(meta.extension).to eq(".otf")
    end

    it "accepts string names as well as symbols" do
      expect(described_class.resolve("ttf").name).to eq(:ttf)
    end

    it "raises ArgumentError for unknown formats" do
      expect { described_class.resolve(:woff) }
        .to raise_error(ArgumentError, /unknown format: :woff/)
    end

    it "freezes no internal state — instances are immutable by contract" do
      meta = described_class.resolve(:ttf)
      expect(meta).to respond_to(:name, :compiler_class, :collection_format,
                                 :extension)
      expect(meta).not_to respond_to(:name=)
    end
  end
end
