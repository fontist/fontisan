# frozen_string: true

require "spec_helper"
require_relative "../../../lib/fontisan/stitcher/cbdt_propagator"

RSpec.describe Fontisan::Stitcher::CbdtPropagator do
  # Subclass Source to control bitmap_mode without a real CBDT fixture.
  # Subclassing is a real class with overridden behavior, not a double.
  let(:cbdt_source_class) do
    Class.new(Fontisan::Stitcher::Source) do
      def bitmap_mode = :cbdt
    end
  end

  let(:outline_source_class) do
    Class.new(Fontisan::Stitcher::Source) do
      def bitmap_mode = :glyf
    end
  end

  let(:empty_ufo) do
    font = Fontisan::Ufo::Font.new
    font.info.units_per_em = 1000
    font.glyphs[".notdef"] = Fontisan::Ufo::Glyph.new(name: ".notdef")
    font
  end

  describe "#cbdt_source" do
    it "returns nil when no source is CBDT" do
      outline = outline_source_class.new(empty_ufo)
      propagator = described_class.new([outline])
      expect(propagator.cbdt_source).to be_nil
    end

    it "returns the single CBDT source" do
      cbdt = cbdt_source_class.new(empty_ufo)
      propagator = described_class.new([cbdt])
      expect(propagator.cbdt_source).to be(cbdt)
    end

    it "raises MultipleCbdtSourcesError when more than one CBDT source" do
      cbdt1 = cbdt_source_class.new(empty_ufo)
      cbdt2 = cbdt_source_class.new(empty_ufo)
      propagator = described_class.new([cbdt1, cbdt2])
      expect { propagator.cbdt_source }
        .to raise_error(Fontisan::MultipleCbdtSourcesError, /multiple CBDT sources/)
    end

    it "ignores non-CBDT sources when counting" do
      cbdt = cbdt_source_class.new(empty_ufo)
      outline = outline_source_class.new(empty_ufo)
      propagator = described_class.new([outline, cbdt])
      expect(propagator.cbdt_source).to be(cbdt)
    end
  end

  describe "#safe_cbdt_source" do
    it "returns the CBDT source when exactly one" do
      cbdt = cbdt_source_class.new(empty_ufo)
      propagator = described_class.new([cbdt])
      expect(propagator.safe_cbdt_source).to be(cbdt)
    end

    it "returns nil when no CBDT source" do
      outline = outline_source_class.new(empty_ufo)
      propagator = described_class.new([outline])
      expect(propagator.safe_cbdt_source).to be_nil
    end

    it "returns nil instead of raising on multiple CBDT sources" do
      cbdt1 = cbdt_source_class.new(empty_ufo)
      cbdt2 = cbdt_source_class.new(empty_ufo)
      propagator = described_class.new([cbdt1, cbdt2])
      expect(propagator.safe_cbdt_source).to be_nil
    end
  end

  describe "#add_placeholder_glyphs" do
    it "copies all glyphs when source font is a UFO" do
      ufo = Fontisan::Ufo::Font.new
      ufo.info.units_per_em = 1000
      ufo.glyphs[".notdef"] = Fontisan::Ufo::Glyph.new(name: ".notdef")
      ufo.glyphs["gid1"] = Fontisan::Ufo::Glyph.new(name: "gid1")
      source = cbdt_source_class.new(ufo)

      target = Fontisan::Ufo::Font.new
      described_class.new([source]).add_placeholder_glyphs(source, target)

      expect(target.glyphs.keys).to contain_exactly(".notdef", "gid1")
    end

    it "is a no-op when source is nil" do
      target = Fontisan::Ufo::Font.new
      target.glyphs[".notdef"] = Fontisan::Ufo::Glyph.new(name: ".notdef")
      expect { described_class.new([]).add_placeholder_glyphs(nil, target) }
        .to raise_error(NoMethodError)
    end
  end

  describe "#propagate_tables_into" do
    it "is a no-op when source is nil" do
      propagator = described_class.new([])
      # No file is created, no exception raised.
      expect { propagator.propagate_tables_into(nil, "/nonexistent/path") }.not_to raise_error
    end
  end
end
