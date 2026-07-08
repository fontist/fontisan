# frozen_string: true

require "spec_helper"
require_relative "../../../lib/fontisan/ufo/layer"
require_relative "../../../lib/fontisan/ufo/glyph"

# Contract tests for the Layer naming invariants. The Layer is a
# Hash-keyed collection and the key is the glyph name; that makes name
# collisions data-loss events. The contract:
#
#   +#add+::  raises GlyphExistsError on collision (the safe default —
#             never silently overwrites)
#   +#put+::  explicit overwrite path for callers who have decided the
#             previous glyph should be discarded
#
# Stitcher collaborators that need auto-renaming use
# +Stitcher::UniqueGlyphName.in(target, base)+ to allocate a free name
# before +#add+.
RSpec.describe Fontisan::Ufo::Layer do
  let(:glyph_a) { Fontisan::Ufo::Glyph.new(name: "A") }
  let(:glyph_a_duplicate) { Fontisan::Ufo::Glyph.new(name: "A") }
  let(:glyph_b) { Fontisan::Ufo::Glyph.new(name: "B") }

  describe "#add" do
    it "inserts the first glyph with a given name" do
      layer = described_class.new
      layer.add(glyph_a)
      expect(layer.size).to eq(1)
      expect(layer["A"]).to be(glyph_a)
    end

    it "raises GlyphExistsError when the name is already taken" do
      layer = described_class.new
      layer.add(glyph_a)

      expect { layer.add(glyph_a_duplicate) }
        .to raise_error(Fontisan::Ufo::Layer::GlyphExistsError, /"A"/)
    end

    it "preserves the original glyph when a second add raises" do
      layer = described_class.new
      layer.add(glyph_a)

      expect { layer.add(glyph_a_duplicate) }.to raise_error(StandardError)
      expect(layer["A"]).to be(glyph_a),
                              "original glyph must NOT be replaced when add raises"
    end

    it "inserts glyphs with distinct names without raising" do
      layer = described_class.new
      layer.add(glyph_a)
      layer.add(glyph_b)
      expect(layer.size).to eq(2)
    end
  end

  describe "#put" do
    it "overwrites an existing glyph with the same name" do
      layer = described_class.new
      layer.add(glyph_a)
      layer.put(glyph_a_duplicate)

      expect(layer.size).to eq(1)
      expect(layer["A"]).to be(glyph_a_duplicate)
    end

    it "inserts a glyph whose name is not yet present" do
      layer = described_class.new
      layer.put(glyph_a)
      expect(layer["A"]).to be(glyph_a)
    end
  end

  describe "GlyphExistsError" do
    it "exposes the colliding name for programmatic handling" do
      layer = described_class.new
      layer.add(glyph_a)

      begin
        layer.add(glyph_a_duplicate)
      rescue described_class::GlyphExistsError => e
        expect(e.name).to eq("A")
      end
    end
  end
end
