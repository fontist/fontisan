# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cff/dict_builder"
require "fontisan/tables/cff/dict"

RSpec.describe Fontisan::Tables::Cff::DictBuilder do
  describe ".build" do
    context "with empty hash" do
      it "builds empty DICT" do
        dict_data = described_class.build({})

        expect(dict_data).to be_a(String)
        expect(dict_data.encoding).to eq(Encoding::BINARY)
        expect(dict_data.bytesize).to eq(0)
        expect(dict_data).to eq("".b)
      end

      it "can be parsed back" do
        dict_data = described_class.build({})
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict.empty?).to be true
        expect(dict.size).to eq(0)
      end
    end

    context "with single operator" do
      let(:dict_hash) { { version: 391 } }

      it "builds valid DICT" do
        dict_data = described_class.build(dict_hash)

        expect(dict_data).to be_a(String)
        expect(dict_data.encoding).to eq(Encoding::BINARY)
        expect(dict_data.bytesize).to be > 0
      end

      it "can be parsed back" do
        dict_data = described_class.build(dict_hash)
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(391)
      end
    end

    context "with multiple operators" do
      let(:dict_hash) do
        {
          version: 391,
          notice: 392,
          full_name: 393,
          family_name: 394,
        }
      end

      it "builds valid DICT" do
        dict_data = described_class.build(dict_hash)

        expect(dict_data).to be_a(String)
        expect(dict_data.encoding).to eq(Encoding::BINARY)
      end

      it "can be parsed back" do
        dict_data = described_class.build(dict_hash)
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(391)
        expect(dict[:notice]).to eq(392)
        expect(dict[:full_name]).to eq(393)
        expect(dict[:family_name]).to eq(394)
      end
    end

    context "with array values" do
      let(:dict_hash) { { font_matrix: [0.001, 0, 0, 0.001, 0, 0] } }

      it "encodes array correctly" do
        dict_data = described_class.build(dict_hash)
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:font_matrix]).to be_a(Array)
        expect(dict[:font_matrix].length).to eq(6)
      end
    end

    context "with two-byte operators" do
      let(:dict_hash) do
        {
          copyright: 395,
          is_fixed_pitch: 0,
          italic_angle: 0,
        }
      end

      it "builds valid DICT with escape operators" do
        dict_data = described_class.build(dict_hash)
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:copyright]).to eq(395)
        expect(dict[:is_fixed_pitch]).to eq(0)
        expect(dict[:italic_angle]).to eq(0)
      end
    end
  end

  describe "integer encoding" do
    context "with small integers (-107 to +107)" do
      it "encodes -107" do
        dict_data = described_class.build({ version: -107 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(-107)
      end

      it "encodes 0" do
        dict_data = described_class.build({ version: 0 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(0)
      end

      it "encodes 107" do
        dict_data = described_class.build({ version: 107 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(107)
      end

      it "uses single-byte encoding" do
        dict_data = described_class.build({ version: 50 })

        # Small integers use 2 bytes: operand + operator
        expect(dict_data.bytesize).to eq(2)
      end
    end

    context "with medium positive integers (108 to 1131)" do
      it "encodes 108" do
        dict_data = described_class.build({ version: 108 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(108)
      end

      it "encodes 500" do
        dict_data = described_class.build({ version: 500 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(500)
      end

      it "encodes 1131" do
        dict_data = described_class.build({ version: 1131 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(1131)
      end

      it "uses two-byte encoding" do
        dict_data = described_class.build({ version: 500 })

        # Medium integers use 3 bytes: 2-byte operand + operator
        expect(dict_data.bytesize).to eq(3)
      end
    end

    context "with medium negative integers (-1131 to -108)" do
      it "encodes -108" do
        dict_data = described_class.build({ version: -108 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(-108)
      end

      it "encodes -500" do
        dict_data = described_class.build({ version: -500 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(-500)
      end

      it "encodes -1131" do
        dict_data = described_class.build({ version: -1131 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(-1131)
      end
    end

    context "with large integers requiring 3-byte encoding" do
      it "encodes 5000" do
        dict_data = described_class.build({ version: 5000 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(5000)
      end

      it "encodes -5000" do
        dict_data = described_class.build({ version: -5000 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(-5000)
      end

      it "encodes 32767" do
        dict_data = described_class.build({ version: 32767 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(32767)
      end

      it "encodes -32768" do
        dict_data = described_class.build({ version: -32768 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(-32768)
      end
    end

    context "with large integers requiring 5-byte encoding" do
      it "encodes 100000" do
        dict_data = described_class.build({ version: 100000 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(100000)
      end

      it "encodes -100000" do
        dict_data = described_class.build({ version: -100000 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(-100000)
      end
    end
  end

  describe "real number encoding" do
    context "with simple real numbers" do
      it "encodes 0.5" do
        dict_data = described_class.build({ stroke_width: 0.5 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:stroke_width]).to be_within(0.001).of(0.5)
      end

      it "encodes 1.5" do
        dict_data = described_class.build({ stroke_width: 1.5 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:stroke_width]).to be_within(0.001).of(1.5)
      end

      it "encodes 0.001" do
        dict_data = described_class.build({ stroke_width: 0.001 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:stroke_width]).to be_within(0.0001).of(0.001)
      end
    end

    context "with negative real numbers" do
      it "encodes -12.5" do
        dict_data = described_class.build({ italic_angle: -12.5 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:italic_angle]).to be_within(0.001).of(-12.5)
      end
    end

    context "with real numbers in arrays" do
      it "encodes font matrix" do
        matrix = [0.001, 0.0, 0.0, 0.001, 0.0, 0.0]
        dict_data = described_class.build({ font_matrix: matrix })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        result = dict[:font_matrix]
        expect(result).to be_a(Array)
        expect(result.length).to eq(6)
        result.each_with_index do |val, i|
          expect(val).to be_within(0.0001).of(matrix[i])
        end
      end
    end
  end

  describe "round-trip validation" do
    context "with simple dict" do
      let(:test_dict) do
        {
          version: 391,
          notice: 392,
          family_name: 394,
        }
      end

      it "preserves data through build → parse → build cycle" do
        # Build from hash
        dict_data1 = described_class.build(test_dict)

        # Parse back
        dict = Fontisan::Tables::Cff::Dict.new(dict_data1)
        parsed_hash = dict.to_h

        # Build again from parsed hash
        dict_data2 = described_class.build(parsed_hash)

        # Parse again to compare values
        dict2 = Fontisan::Tables::Cff::Dict.new(dict_data2)

        test_dict.each do |key, value|
          expect(dict2[key]).to eq(value)
        end
      end
    end

    context "with complex dict" do
      let(:test_dict) do
        {
          version: 391,
          notice: 392,
          copyright: 395,
          italic_angle: -12,
          underline_position: -100,
          underline_thickness: 50,
          is_fixed_pitch: 0,
          paint_type: 0,
        }
      end

      it "preserves all values correctly" do
        dict_data = described_class.build(test_dict)
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        test_dict.each do |key, value|
          expect(dict[key]).to eq(value)
        end
      end
    end

    context "with mixed integer sizes" do
      let(:test_dict) do
        {
          version: 50,        # Small int
          notice: 500,        # Medium int
          full_name: 5000,    # Large int (3-byte)
          family_name: 100000, # Large int (5-byte)
        }
      end

      it "encodes all sizes correctly" do
        dict_data = described_class.build(test_dict)
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(50)
        expect(dict[:notice]).to eq(500)
        expect(dict[:full_name]).to eq(5000)
        expect(dict[:family_name]).to eq(100000)
      end
    end
  end

  describe "error handling" do
    context "with invalid input type" do
      it "raises ArgumentError for non-Hash" do
        expect do
          described_class.build("not a hash")
        end.to raise_error(ArgumentError, /dict_hash must be Hash/)
      end

      it "raises ArgumentError for nil" do
        expect do
          described_class.build(nil)
        end.to raise_error(ArgumentError, /dict_hash must be Hash/)
      end

      it "raises ArgumentError for Array" do
        expect do
          described_class.build([1, 2, 3])
        end.to raise_error(ArgumentError, /dict_hash must be Hash/)
      end
    end

    context "with unknown operators" do
      it "raises ArgumentError for unknown operator" do
        expect do
          described_class.build({ unknown_operator: 123 })
        end.to raise_error(ArgumentError, /Unknown operator: unknown_operator/)
      end
    end
  end

  describe "operator encoding" do
    context "with single-byte operators" do
      it "encodes version (0)" do
        dict_data = described_class.build({ version: 391 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:version]).to eq(391)
      end

      it "encodes notice (1)" do
        dict_data = described_class.build({ notice: 392 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:notice]).to eq(392)
      end

      it "encodes weight (4)" do
        dict_data = described_class.build({ weight: 400 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:weight]).to eq(400)
      end
    end

    context "with two-byte operators (12 prefix)" do
      it "encodes copyright (12, 0)" do
        dict_data = described_class.build({ copyright: 395 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:copyright]).to eq(395)
      end

      it "encodes is_fixed_pitch (12, 1)" do
        dict_data = described_class.build({ is_fixed_pitch: 0 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:is_fixed_pitch]).to eq(0)
      end

      it "encodes italic_angle (12, 2)" do
        dict_data = described_class.build({ italic_angle: -12 })
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)

        expect(dict[:italic_angle]).to eq(-12)
      end
    end
  end

  describe "binary output format" do
    let(:dict_hash) { { version: 391, notice: 392 } }

    it "produces binary string" do
      dict_data = described_class.build(dict_hash)

      expect(dict_data.encoding).to eq(Encoding::BINARY)
      expect(dict_data.valid_encoding?).to be true
    end

    it "contains operands and operators" do
      dict_data = described_class.build(dict_hash)

      # Should contain encoded operands and operators
      expect(dict_data.bytesize).to be > 0
    end
  end

  describe "performance considerations" do
    it "handles many operators efficiently" do
      large_dict = {
        version: 391,
        notice: 392,
        full_name: 393,
        family_name: 394,
        weight: 400,
        copyright: 395,
        is_fixed_pitch: 0,
        italic_angle: -12,
        underline_position: -100,
        underline_thickness: 50,
      }

      expect do
        dict_data = described_class.build(large_dict)
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)
        expect(dict.size).to eq(10)
      end.not_to raise_error
    end

    it "handles large arrays efficiently" do
      dict_hash = { font_matrix: Array.new(100, 0.001) }

      expect do
        dict_data = described_class.build(dict_hash)
        dict = Fontisan::Tables::Cff::Dict.new(dict_data)
        expect(dict[:font_matrix].length).to eq(100)
      end.not_to raise_error
    end
  end

  describe "integration with Dict parser" do
    it "produces output compatible with Dict parser" do
      dict_hash = {
        version: 391,
        notice: 392,
        family_name: 394,
        copyright: 395,
        italic_angle: -12,
      }

      dict_data = described_class.build(dict_hash)
      dict = Fontisan::Tables::Cff::Dict.new(dict_data)

      # Verify all parser methods work
      expect(dict.size).to eq(5)
      expect(dict.empty?).to be false
      expect(dict.has_key?(:version)).to be true
      expect(dict.has_key?(:copyright)).to be true
      expect(dict.keys).to include(:version, :notice, :family_name, :copyright,
                                   :italic_angle)
      expect(dict.values).to include(391, 392, 394, 395, -12)
    end
  end
end
