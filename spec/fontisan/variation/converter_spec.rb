# frozen_string_literal: true

require "spec_helper"
require "fontisan/variation/converter"

RSpec.describe Fontisan::Variation::Converter do
  let(:font) { instance_double(Fontisan::TrueTypeFont) }
  let(:axes) do
    [
      double(
        "VariationAxisRecord",
        axis_tag: "wght",
        min_value: 400.0,
        default_value: 400.0,
        max_value: 700.0
      ),
    ]
  end
  let(:converter) { described_class.new(font, axes) }

  describe "#initialize" do
    it "initializes with font and axes" do
      expect(converter.font).to eq(font)
      expect(converter.axes).to eq(axes)
    end

    it "handles nil axes" do
      converter = described_class.new(font, nil)
      expect(converter.axes).to eq([])
    end
  end

  describe "#can_convert?" do
    context "when font has gvar table" do
      before do
        allow(font).to receive(:has_table?).with("gvar").and_return(true)
        allow(font).to receive(:has_table?).with("CFF2").and_return(false)
      end

      it "returns true if axes present" do
        expect(converter.can_convert?).to be true
      end
    end

    context "when font has CFF2 table" do
      before do
        allow(font).to receive(:has_table?).with("gvar").and_return(false)
        allow(font).to receive(:has_table?).with("CFF2").and_return(true)
      end

      it "returns true if axes present" do
        expect(converter.can_convert?).to be true
      end
    end

    context "when font has no variation tables" do
      before do
        allow(font).to receive(:has_table?).with("gvar").and_return(false)
        allow(font).to receive(:has_table?).with("CFF2").and_return(false)
      end

      it "returns false" do
        expect(converter.can_convert?).to be false
      end
    end

    context "when no axes present" do
      let(:converter) { described_class.new(font, []) }

      before do
        allow(font).to receive(:has_table?).with("gvar").and_return(true)
      end

      it "returns false" do
        expect(converter.can_convert?).to be false
      end
    end
  end

  describe "#gvar_to_blend" do
    let(:gvar_table) { instance_double(Fontisan::Tables::Gvar) }
    let(:glyf_table) { instance_double(Fontisan::Tables::Glyf) }
    let(:glyph_id) { 42 }

    before do
      allow(font).to receive(:has_table?).with("gvar").and_return(true)
      allow(font).to receive(:has_table?).with("glyf").and_return(true)
      allow(font).to receive(:table).with("gvar").and_return(gvar_table)
      allow(font).to receive(:table).with("glyf").and_return(glyf_table)
    end

    context "when gvar table is missing" do
      before do
        allow(font).to receive(:has_table?).with("gvar").and_return(false)
      end

      it "returns nil" do
        expect(converter.gvar_to_blend(glyph_id)).to be_nil
      end
    end

    context "when glyf table is missing" do
      before do
        allow(font).to receive(:has_table?).with("glyf").and_return(false)
      end

      it "returns nil" do
        expect(converter.gvar_to_blend(glyph_id)).to be_nil
      end
    end

    context "when glyph has no tuple variations" do
      before do
        allow(gvar_table).to receive(:glyph_tuple_variations)
          .with(glyph_id)
          .and_return(nil)
      end

      it "returns nil" do
        expect(converter.gvar_to_blend(glyph_id)).to be_nil
      end
    end

    context "with simple single tuple, single axis" do
      let(:tuple_data) do
        {
          tuple_count: 1,
          has_shared_points: false,
          data_offset: 0,
          tuples: [
            {
              data_size: 10,
              embedded_peak: true,
              intermediate: false,
              private_points: false,
              shared_index: nil,
              peak: [0.5], # wght at 550 (normalized to 0.5)
              deltas: [
                { x: 10, y: 20 },
                { x: -5, y: 15 },
              ],
            },
          ],
          point_count: 2,
        }
      end

      before do
        allow(gvar_table).to receive(:glyph_tuple_variations)
          .with(glyph_id)
          .and_return(tuple_data)
      end

      it "converts to blend format" do
        result = converter.gvar_to_blend(glyph_id)

        expect(result).to be_a(Hash)
        expect(result[:num_regions]).to eq(1)
        expect(result[:num_axes]).to eq(1)
        expect(result[:regions]).to be_an(Array)
        expect(result[:regions].length).to eq(1)
        expect(result[:point_deltas]).to be_an(Array)
        expect(result[:point_deltas].length).to eq(2)
      end

      it "builds region from tuple peak" do
        result = converter.gvar_to_blend(glyph_id)
        region = result[:regions].first

        expect(region).to have_key("wght")
        expect(region["wght"][:peak]).to eq(0.5)
      end

      it "extracts point deltas" do
        result = converter.gvar_to_blend(glyph_id)
        point_deltas = result[:point_deltas]

        # First point
        expect(point_deltas[0]).to be_an(Array)
        expect(point_deltas[0].length).to eq(1) # One region

        # Second point
        expect(point_deltas[1]).to be_an(Array)
        expect(point_deltas[1].length).to eq(1) # One region
      end
    end

    context "with multiple tuples, single axis" do
      let(:tuple_data) do
        {
          tuple_count: 2,
          has_shared_points: false,
          data_offset: 0,
          tuples: [
            {
              peak: [0.5],
              deltas: [{ x: 10, y: 20 }],
            },
            {
              peak: [1.0],
              deltas: [{ x: 20, y: 40 }],
            },
          ],
          point_count: 1,
        }
      end

      before do
        allow(gvar_table).to receive(:glyph_tuple_variations)
          .with(glyph_id)
          .and_return(tuple_data)
      end

      it "converts all tuples to regions" do
        result = converter.gvar_to_blend(glyph_id)

        expect(result[:num_regions]).to eq(2)
        expect(result[:regions].length).to eq(2)
      end

      it "creates deltas for all regions per point" do
        result = converter.gvar_to_blend(glyph_id)

        # One point, two regions worth of deltas
        expect(result[:point_deltas].length).to eq(1)
        expect(result[:point_deltas][0].length).to eq(2)
      end
    end

    context "with single tuple, multiple axes" do
      let(:axes) do
        [
          double("VariationAxisRecord", axis_tag: "wght"),
          double("VariationAxisRecord", axis_tag: "wdth"),
        ]
      end
      let(:converter) { described_class.new(font, axes) }
      let(:tuple_data) do
        {
          tuple_count: 1,
          tuples: [
            {
              peak: [0.5, 0.3], # wght=0.5, wdth=0.3
              deltas: [{ x: 10, y: 20 }],
            },
          ],
          point_count: 1,
        }
      end

      before do
        allow(gvar_table).to receive(:glyph_tuple_variations)
          .with(glyph_id)
          .and_return(tuple_data)
      end

      it "creates region with all axes" do
        result = converter.gvar_to_blend(glyph_id)

        region = result[:regions].first
        expect(region).to have_key("wght")
        expect(region).to have_key("wdth")
        expect(region["wght"][:peak]).to eq(0.5)
        expect(region["wdth"][:peak]).to eq(0.3)
      end

      it "sets num_axes correctly" do
        result = converter.gvar_to_blend(glyph_id)
        expect(result[:num_axes]).to eq(2)
      end
    end

    context "with intermediate region (start/end)" do
      let(:tuple_data) do
        {
          tuple_count: 1,
          tuples: [
            {
              peak: [0.5],
              start: [0.25],
              end: [0.75],
              deltas: [{ x: 10, y: 20 }],
            },
          ],
          point_count: 1,
        }
      end

      before do
        allow(gvar_table).to receive(:glyph_tuple_variations)
          .with(glyph_id)
          .and_return(tuple_data)
      end

      it "includes start and end in region" do
        result = converter.gvar_to_blend(glyph_id)
        region = result[:regions].first

        expect(region["wght"][:start]).to eq(0.25)
        expect(region["wght"][:peak]).to eq(0.5)
        expect(region["wght"][:end]).to eq(0.75)
      end
    end

    context "with empty glyph (no points)" do
      let(:tuple_data) do
        {
          tuple_count: 1,
          tuples: [{ peak: [0.5], deltas: [] }],
          point_count: 0,
        }
      end

      before do
        allow(gvar_table).to receive(:glyph_tuple_variations)
          .with(glyph_id)
          .and_return(tuple_data)
      end

      it "returns empty point deltas" do
        result = converter.gvar_to_blend(glyph_id)
        expect(result[:point_deltas]).to eq([])
      end
    end
  end

  describe "#blend_to_gvar" do
    let(:cff2_table) { instance_double(Fontisan::Tables::Cff2) }
    let(:glyph_id) { 42 }

    before do
      allow(font).to receive(:has_table?).with("CFF2").and_return(true)
      allow(font).to receive(:table).with("CFF2").and_return(cff2_table)
    end

    context "when CFF2 table is missing" do
      before do
        allow(font).to receive(:has_table?).with("CFF2").and_return(false)
      end

      it "returns nil" do
        expect(converter.blend_to_gvar(glyph_id)).to be_nil
      end
    end

    context "when charstring is missing" do
      before do
        allow(cff2_table).to receive(:charstring_for_glyph).with(glyph_id).and_return(nil)
      end

      it "returns nil" do
        expect(converter.blend_to_gvar(glyph_id)).to be_nil
      end
    end

    context "when charstring has no blend data" do
      let(:charstring) do
        double("CharstringParser",
               parse: true,
               instance_variable_get: nil,
               blend_data: [])
      end

      before do
        allow(cff2_table).to receive(:charstring_for_glyph).with(glyph_id).and_return(charstring)
      end

      it "returns nil" do
        expect(converter.blend_to_gvar(glyph_id)).to be_nil
      end
    end

    context "with blend data" do
      let(:charstring) do
        double("CharstringParser",
               parse: true,
               instance_variable_get: true,
               blend_data: [
                 {
                   num_values: 2,
                   num_axes: 1,
                   blends: [
                     { base: 100, deltas: [10] },
                     { base: 200, deltas: [20] },
                   ],
                 },
               ])
      end

      before do
        allow(cff2_table).to receive(:charstring_for_glyph).with(glyph_id).and_return(charstring)
      end

      it "converts blend data to tuples" do
        result = converter.blend_to_gvar(glyph_id)

        expect(result).to be_a(Hash)
        expect(result).to have_key(:tuples)
        expect(result).to have_key(:point_count)
      end

      it "creates tuples from blend operations" do
        result = converter.blend_to_gvar(glyph_id)

        expect(result[:tuples]).to be_an(Array)
        expect(result[:tuples]).not_to be_empty
      end
    end
  end

  describe "#convert_all_gvar_to_blend" do
    let(:gvar_table) { instance_double(Fontisan::Tables::Gvar) }
    let(:glyf_table) { instance_double(Fontisan::Tables::Glyf) }
    let(:glyph_count) { 3 }

    before do
      allow(font).to receive(:has_table?).with("gvar").and_return(true)
      allow(font).to receive(:has_table?).with("glyf").and_return(true)
      allow(font).to receive(:has_table?).with("CFF2").and_return(false)
      allow(font).to receive(:table).with("gvar").and_return(gvar_table)
      allow(font).to receive(:table).with("glyf").and_return(glyf_table)
    end

    context "when can_convert is false" do
      let(:converter) { described_class.new(font, []) }

      it "returns empty hash" do
        result = converter.convert_all_gvar_to_blend(glyph_count)
        expect(result).to eq({})
      end
    end

    context "when only some glyphs have variations" do
      before do
        # Glyph 0: has variations
        allow(gvar_table).to receive(:glyph_tuple_variations).with(0).and_return(
          {
            tuple_count: 1,
            tuples: [{ peak: [0.5], deltas: [{ x: 10, y: 20 }] }],
            point_count: 1,
          }
        )

        # Glyph 1: no variations
        allow(gvar_table).to receive(:glyph_tuple_variations).with(1).and_return(nil)

        # Glyph 2: has variations
        allow(gvar_table).to receive(:glyph_tuple_variations).with(2).and_return(
          {
            tuple_count: 1,
            tuples: [{ peak: [1.0], deltas: [{ x: 5, y: 10 }] }],
            point_count: 1,
          }
        )
      end

      it "converts only glyphs with variations" do
        result = converter.convert_all_gvar_to_blend(glyph_count)

        expect(result.keys).to contain_exactly(0, 2)
        expect(result[0]).to be_a(Hash)
        expect(result[0][:num_regions]).to eq(1)
        expect(result[2]).to be_a(Hash)
        expect(result[2][:num_regions]).to eq(1)
      end
    end

    context "when all glyphs have variations" do
      before do
        (0...glyph_count).each do |glyph_id|
          allow(gvar_table).to receive(:glyph_tuple_variations).with(glyph_id).and_return(
            {
              tuple_count: 1,
              tuples: [{ peak: [0.5], deltas: [{ x: glyph_id * 10, y: glyph_id * 20 }] }],
              point_count: 1,
            }
          )
        end
      end

      it "converts all glyphs" do
        result = converter.convert_all_gvar_to_blend(glyph_count)

        expect(result.keys).to contain_exactly(0, 1, 2)
        result.each_value do |blend_data|
          expect(blend_data).to be_a(Hash)
          expect(blend_data).to have_key(:regions)
          expect(blend_data).to have_key(:point_deltas)
        end
      end
    end
  end

  describe "#convert_all_blend_to_gvar" do
    let(:cff2_table) { instance_double(Fontisan::Tables::Cff2) }
    let(:glyph_count) { 3 }

    before do
      allow(font).to receive(:has_table?).with("gvar").and_return(false)
      allow(font).to receive(:has_table?).with("CFF2").and_return(true)
      allow(font).to receive(:table).with("CFF2").and_return(cff2_table)
    end

    context "when can_convert is false" do
      let(:converter) { described_class.new(font, []) }

      it "returns empty hash" do
        result = converter.convert_all_blend_to_gvar(glyph_count)
        expect(result).to eq({})
      end
    end

    context "with charstrings that have blend data" do
      let(:charstring_with_blend) do
        double("CharstringParser",
               parse: true,
               instance_variable_get: true,
               blend_data: [
                 {
                   num_values: 1,
                   num_axes: 1,
                   blends: [{ base: 100, deltas: [10] }],
                 },
               ])
      end

      let(:charstring_without_blend) do
        double("CharstringParser",
               parse: true,
               instance_variable_get: true,
               blend_data: [])
      end

      before do
        # Glyph 0: has blend data
        allow(cff2_table).to receive(:charstring_for_glyph).with(0).and_return(charstring_with_blend)
        # Glyph 1: no blend data
        allow(cff2_table).to receive(:charstring_for_glyph).with(1).and_return(charstring_without_blend)
        # Glyph 2: has blend data
        allow(cff2_table).to receive(:charstring_for_glyph).with(2).and_return(charstring_with_blend)
      end

      it "converts only glyphs with blend data" do
        result = converter.convert_all_blend_to_gvar(glyph_count)

        expect(result.keys).to contain_exactly(0, 2)
        expect(result[0]).to be_a(Hash)
        expect(result[0]).to have_key(:tuples)
        expect(result[2]).to be_a(Hash)
        expect(result[2]).to have_key(:tuples)
      end
    end
  end

  describe "helper methods" do
    describe "#encode_blend_operator" do
      it "encodes base value and deltas" do
        result = converter.send(:encode_blend_operator, 100, [10, 20])
        expect(result).to eq([100, 10, 20, 2, 1])
      end

      it "handles single delta" do
        result = converter.send(:encode_blend_operator, 50, [5])
        expect(result).to eq([50, 5, 1, 1])
      end

      it "handles no deltas" do
        result = converter.send(:encode_blend_operator, 50, [])
        expect(result).to eq([50, 0, 1])
      end
    end

    describe "#decode_blend_operator" do
      it "decodes blend operator arguments" do
        args = [100, 10, 20, 2, 1]
        result = converter.send(:decode_blend_operator, args)

        expect(result[:base]).to eq(100)
        expect(result[:deltas]).to eq([10, 20])
      end

      it "handles single delta" do
        args = [50, 5, 1, 1]
        result = converter.send(:decode_blend_operator, args)

        expect(result[:base]).to eq(50)
        expect(result[:deltas]).to eq([5])
      end

      it "handles invalid arguments" do
        args = [100]
        result = converter.send(:decode_blend_operator, args)

        expect(result[:base]).to eq(0)
        expect(result[:deltas]).to eq([])
      end
    end

    describe "#build_region_from_tuple" do
      let(:tuple) do
        {
          peak: [0.5],
          start: [0.25],
          end: [0.75],
        }
      end

      it "builds region with all coordinates" do
        region = converter.send(:build_region_from_tuple, tuple)

        expect(region).to have_key("wght")
        expect(region["wght"][:start]).to eq(0.25)
        expect(region["wght"][:peak]).to eq(0.5)
        expect(region["wght"][:end]).to eq(0.75)
      end

      it "uses default values when not provided" do
        tuple = { peak: [0.5] }
        region = converter.send(:build_region_from_tuple, tuple)

        expect(region["wght"][:start]).to eq(-1.0)
        expect(region["wght"][:peak]).to eq(0.5)
        expect(region["wght"][:end]).to eq(1.0)
      end
    end

    describe "#build_tuple_from_region" do
      let(:region) do
        {
          "wght" => {
            start: 0.25,
            peak: 0.5,
            end: 0.75,
          },
        }
      end
      let(:point_deltas) do
        [
          [{ x: 10, y: 20 }], # Point 0, region 0
          [{ x: -5, y: 15 }], # Point 1, region 0
        ]
      end

      it "builds tuple with peak/start/end arrays" do
        tuple = converter.send(
          :build_tuple_from_region,
          region,
          point_deltas,
          0
        )

        expect(tuple[:peak]).to eq([0.5])
        expect(tuple[:start]).to eq([0.25])
        expect(tuple[:end]).to eq([0.75])
      end

      it "extracts deltas for region" do
        tuple = converter.send(
          :build_tuple_from_region,
          region,
          point_deltas,
          0
        )

        expect(tuple[:deltas]).to eq([
                                       { x: 10, y: 20 },
                                       { x: -5, y: 15 },
                                     ])
      end
    end
  end
end
