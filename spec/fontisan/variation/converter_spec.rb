# frozen_string_literal: true

require "spec_helper"
require "fontisan/variation/converter"

RSpec.describe Fontisan::Variation::VariationConverter do
  let(:font) { double("Font") }
  let(:axis) do
    double("Axis",
           axis_tag: "wght",
           min_value: 400.0,
           default_value: 400.0,
           max_value: 900.0)
  end
  let(:axes) { [axis] }
  let(:converter) { described_class.new(font, axes) }

  describe "#initialize" do
    it "stores font and axes" do
      expect(converter.font).to eq(font)
      expect(converter.axes).to eq(axes)
    end

    it "handles nil axes" do
      converter = described_class.new(font, nil)
      expect(converter.axes).to eq([])
    end
  end

  describe "#can_convert?" do
    context "when font has no axes" do
      let(:converter) { described_class.new(font, []) }

      it "returns false" do
        allow(font).to receive(:has_table?).and_return(true)
        expect(converter.can_convert?).to be false
      end
    end

    context "when font has axes but no variation tables" do
      it "returns false" do
        allow(font).to receive(:has_table?).with("gvar").and_return(false)
        allow(font).to receive(:has_table?).with("CFF2").and_return(false)
        expect(converter.can_convert?).to be false
      end
    end

    context "when font has axes and gvar table" do
      it "returns true" do
        allow(font).to receive(:has_table?).with("gvar").and_return(true)
        allow(font).to receive(:has_table?).with("CFF2").and_return(false)
        expect(converter.can_convert?).to be true
      end
    end

    context "when font has axes and CFF2 table" do
      it "returns true" do
        allow(font).to receive(:has_table?).with("gvar").and_return(false)
        allow(font).to receive(:has_table?).with("CFF2").and_return(true)
        expect(converter.can_convert?).to be true
      end
    end
  end

  describe "#gvar_to_blend" do
    let(:glyph_id) { 42 }

    context "when gvar table is missing" do
      it "returns nil" do
        allow(font).to receive(:has_table?).with("gvar").and_return(false)
        expect(converter.gvar_to_blend(glyph_id)).to be_nil
      end
    end

    context "when glyf table is missing" do
      it "returns nil" do
        allow(font).to receive(:has_table?).with("gvar").and_return(true)
        allow(font).to receive(:has_table?).with("glyf").and_return(false)
        expect(converter.gvar_to_blend(glyph_id)).to be_nil
      end
    end

    context "when tables are present" do
      let(:gvar) { double("gvar") }
      let(:tuple_data) do
        {
          tuples: [
            {
              peak: [0.5],
              start: [-1.0],
              end: [1.0],
            },
          ],
          point_count: 4,
        }
      end

      before do
        allow(font).to receive(:has_table?).with("gvar").and_return(true)
        allow(font).to receive(:has_table?).with("glyf").and_return(true)
        allow(font).to receive(:table).with("gvar").and_return(gvar)
      end

      it "returns nil when glyph has no tuple data" do
        allow(gvar).to receive(:glyph_tuple_variations).with(glyph_id).and_return(nil)
        expect(converter.gvar_to_blend(glyph_id)).to be_nil
      end

      it "converts tuple data to blend format" do
        allow(gvar).to receive(:glyph_tuple_variations).with(glyph_id).and_return(tuple_data)

        result = converter.gvar_to_blend(glyph_id)

        expect(result).to be_a(Hash)
        expect(result).to have_key(:regions)
        expect(result).to have_key(:point_deltas)
        expect(result).to have_key(:num_regions)
        expect(result).to have_key(:num_axes)
        expect(result[:num_regions]).to eq(1)
        expect(result[:num_axes]).to eq(1)
      end
    end
  end

  describe "#blend_to_gvar" do
    let(:glyph_id) { 42 }

    context "when CFF2 table is missing" do
      it "returns nil" do
        allow(font).to receive(:has_table?).with("CFF2").and_return(false)
        expect(converter.blend_to_gvar(glyph_id)).to be_nil
      end
    end

    context "when CFF2 table is present" do
      let(:cff2) { double("CFF2") }

      before do
        allow(font).to receive(:has_table?).with("CFF2").and_return(true)
        allow(font).to receive(:table).with("CFF2").and_return(cff2)
      end

      it "returns nil for now (placeholder implementation)" do
        # This is expected until full CFF2 parsing is implemented
        expect(converter.blend_to_gvar(glyph_id)).to be_nil
      end
    end
  end

  describe "private methods" do
    describe "#build_region_from_tuple" do
      let(:tuple) do
        {
          peak: [0.5, 0.3],
          start: [-1.0, -0.5],
          end: [1.0, 0.8],
        }
      end
      let(:axes) do
        [
          double("Axis", axis_tag: "wght"),
          double("Axis", axis_tag: "wdth"),
        ]
      end
      let(:converter) { described_class.new(font, axes) }

      it "builds region from tuple coordinates" do
        region = converter.send(:build_region_from_tuple, tuple)

        expect(region).to be_a(Hash)
        expect(region).to have_key("wght")
        expect(region).to have_key("wdth")

        expect(region["wght"]).to include(
          start: -1.0,
          peak: 0.5,
          end: 1.0
        )

        expect(region["wdth"]).to include(
          start: -0.5,
          peak: 0.3,
          end: 0.8
        )
      end
    end

    describe "#encode_blend_operator" do
      it "encodes base and deltas in blend format" do
        base = 100
        deltas = [10, 20, 30]

        result = converter.send(:encode_blend_operator, base, deltas)

        # Format: base, delta1, delta2, delta3, K, N
        expect(result).to eq([100, 10, 20, 30, 3, 1])
      end
    end

    describe "#decode_blend_operator" do
      it "decodes blend operator arguments" do
        args = [100, 10, 20, 30, 3, 1]

        result = converter.send(:decode_blend_operator, args)

        expect(result).to eq(base: 100, deltas: [10, 20, 30])
      end

      it "handles empty arguments" do
        result = converter.send(:decode_blend_operator, [])

        expect(result).to eq(base: 0, deltas: [])
      end

      it "handles minimal arguments" do
        result = converter.send(:decode_blend_operator, [100, 0, 1])

        expect(result).to eq(base: 100, deltas: [])
      end
    end
  end
end
