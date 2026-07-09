# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/compile/filters"

RSpec.describe Fontisan::Ufo::Compile::Filters::PropagateAnchors do
  let(:base_glyph) do
    g = Fontisan::Ufo::Glyph.new(name: "A")
    g.add_anchor(Fontisan::Ufo::Anchor.new(x: 100, y: 500, name: "top"))
    g.add_anchor(Fontisan::Ufo::Anchor.new(x: 100, y: -20, name: "bottom"))
    g
  end

  let(:composite) do
    g = Fontisan::Ufo::Glyph.new(name: "Aacute")
    g.add_component(Fontisan::Ufo::Component.new(base_glyph: "A"))
    g
  end

  describe ".run" do
    it "propagates anchors from base glyphs to composite glyphs" do
      described_class.run([base_glyph, composite])

      anchor_keys = composite.anchors.map { |a| [a.name, a.x, a.y] }
      expect(anchor_keys).to contain_exactly(
        ["top", 100.0, 500.0],
        ["bottom", 100.0, -20.0],
      )
    end

    it "applies the component transformation matrix to propagated anchors" do
      composite.components.clear
      composite.add_component(Fontisan::Ufo::Component.new(
                                base_glyph: "A",
                                transformation: Fontisan::Ufo::Transformation.new(
                                  e: 50, f: 10,
                                ),
                              ))

      described_class.run([base_glyph, composite])

      anchor_keys = composite.anchors.map { |a| [a.name, a.x, a.y] }
      expect(anchor_keys).to contain_exactly(
        ["top", 150.0, 510.0],
        ["bottom", 150.0, -10.0],
      )
    end

    it "accepts a raw array matrix on the component" do
      composite.components.clear
      composite.add_component(Fontisan::Ufo::Component.new(
                                base_glyph: "A",
                                transformation: [1, 0, 0, 1, 50, 10], # raw [a,b,c,d,e,f]
                              ))

      described_class.run([base_glyph, composite])

      anchor_keys = composite.anchors.map { |a| [a.name, a.x, a.y] }
      expect(anchor_keys).to contain_exactly(
        ["top", 150.0, 510.0],
        ["bottom", 150.0, -10.0],
      )
    end

    it "does not duplicate anchors the composite already has" do
      # Composite manually placed the same anchor the base would propagate.
      composite.add_anchor(Fontisan::Ufo::Anchor.new(x: 100, y: 500,
                                                     name: "top"))

      described_class.run([base_glyph, composite])

      top_anchors = composite.anchors.select { |a| a.name == "top" }
      expect(top_anchors.size).to eq(1)
    end

    it "leaves glyphs without components unchanged" do
      original = base_glyph.anchors.map { |a| [a.name, a.x, a.y] }
      described_class.run([base_glyph])
      expect(base_glyph.anchors.map { |a| [a.name, a.x, a.y] }).to eq(original)
    end

    it "silently skips components whose base glyph is not in the lookup" do
      composite.components.clear
      composite.add_component(Fontisan::Ufo::Component.new(base_glyph: "Missing"))

      expect { described_class.run([composite]) }.not_to raise_error
      expect(composite.anchors).to be_empty
    end

    it "uses font.glyph(name) for base lookup when :font is provided" do
      font = Fontisan::Ufo::Font.new
      font.glyphs["A"] = base_glyph
      # Note: composite NOT added to font.glyphs, only to the glyphs array,
      # to verify the lookup uses font (not the glyphs array).

      described_class.run([composite], font: font)

      anchor_keys = composite.anchors.map { |a| [a.name, a.x, a.y] }
      expect(anchor_keys).to contain_exactly(
        ["top", 100.0, 500.0],
        ["bottom", 100.0, -20.0],
      )
    end

    it "returns the same glyph array (mutates in place)" do
      glyphs = [base_glyph, composite]
      result = described_class.run(glyphs)
      expect(result).to equal(glyphs)
    end
  end

  describe "Filters::REGISTRY" do
    it "registers PropagateAnchors under :propagate_anchors" do
      expect(Fontisan::Ufo::Compile::Filters::REGISTRY[:propagate_anchors])
        .to eq(described_class)
    end
  end
end
