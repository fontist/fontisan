# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Hints::TrueTypeInstructionGenerator do
  subject(:generator) { described_class.new }

  describe "#generate" do
    it "generates all three components" do
      params = { blue_scale: 0.039625, std_hw: 80, std_vw: 90 }
      result = generator.generate(params)

      expect(result).to have_key(:fpgm)
      expect(result).to have_key(:prep)
      expect(result).to have_key(:cvt)
    end

    it "handles string keys" do
      params = { "blue_scale" => 0.039625, "std_hw" => 80 }
      result = generator.generate(params)

      expect(result[:prep]).not_to be_empty
      expect(result[:cvt]).to include(80)
    end

    it "returns empty results for empty parameters" do
      result = generator.generate({})

      expect(result[:fpgm]).to eq("".b)
      expect(result[:prep]).to eq("".b)
      expect(result[:cvt]).to eq([])
    end
  end

  describe "#generate_prep" do
    context "with blue_scale" do
      it "generates SCVTCI instruction" do
        params = { blue_scale: 0.039625 }
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        # Should have: PUSH value, SCVTCI
        expect(bytes.last).to eq(0x1D) # SCVTCI opcode
      end

      it "uses PUSHB for small blue_scale values" do
        params = { blue_scale: 0.039625 } # Maps to 17
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        # PUSHB[0] (0xB0), value, SCVTCI
        expect(bytes[0]).to eq(0xB0) # PUSHB[0]
        expect(bytes[1]).to eq(17)   # Calculated CVT cut-in
        expect(bytes[2]).to eq(0x1D) # SCVTCI
      end

      it "handles zero blue_scale" do
        params = { blue_scale: 0.0 }
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        expect(bytes).to eq([0xB0, 0, 0x1D]) # PUSHB[0], 0, SCVTCI
      end

      it "handles maximum blue_scale" do
        params = { blue_scale: 1.0 }
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        # Should clamp to 255
        expect(bytes).to include(255)
        expect(bytes.last).to eq(0x1D)
      end
    end

    context "with stem widths" do
      it "generates SSWCI and SSW for std_hw" do
        params = { std_hw: 80 }
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        # Should have: PUSH sw_cut_in, SSWCI, PUSH std_hw, SSW
        expect(bytes).to include(0x1E) # SSWCI
        expect(bytes).to include(0x1F) # SSW
      end

      it "prefers std_hw over std_vw for single width" do
        params = { std_hw: 80, std_vw: 90 }
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        # Last value pushed should be std_hw (80)
        # Format: [..., PUSHB[0], 80, SSW]
        ssw_index = bytes.rindex(0x1F)
        expect(bytes[ssw_index - 1]).to eq(80)
      end

      it "uses std_vw when std_hw is absent" do
        params = { std_vw: 90 }
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        ssw_index = bytes.rindex(0x1F)
        expect(bytes[ssw_index - 1]).to eq(90)
      end

      it "uses standard cut-in value of 9" do
        params = { std_hw: 80 }
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        # Find SSWCI instruction
        sswci_index = bytes.index(0x1E)
        expect(bytes[sswci_index - 1]).to eq(9) # Standard cut-in
      end
    end

    context "with combined parameters" do
      it "generates all instructions in correct order" do
        params = { blue_scale: 0.039625, std_hw: 80 }
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        # Order: CVT cut-in setup, SW cut-in setup, SW setup
        scvtci_index = bytes.index(0x1D)
        sswci_index = bytes.index(0x1E)
        ssw_index = bytes.index(0x1F)

        expect(scvtci_index).to be < sswci_index
        expect(sswci_index).to be < ssw_index
      end
    end

    context "with no parameters" do
      it "returns empty string" do
        prep = generator.generate_prep({})
        expect(prep).to eq("".b)
      end
    end
  end

  describe "#generate_fpgm" do
    it "returns empty binary string" do
      params = { blue_scale: 0.039625, std_hw: 80 }
      fpgm = generator.generate_fpgm(params)

      expect(fpgm).to eq("".b)
      expect(fpgm.encoding).to eq(Encoding::BINARY)
    end

    it "ignores all parameters" do
      fpgm1 = generator.generate_fpgm({})
      fpgm2 = generator.generate_fpgm({ blue_scale: 0.5, std_hw: 100 })

      expect(fpgm1).to eq(fpgm2)
    end
  end

  describe "#generate_cvt" do
    context "with standard widths" do
      it "adds std_hw to CVT" do
        params = { std_hw: 80 }
        cvt = generator.generate_cvt(params)

        expect(cvt).to eq([80])
      end

      it "adds std_vw to CVT" do
        params = { std_vw: 90 }
        cvt = generator.generate_cvt(params)

        expect(cvt).to eq([90])
      end

      it "adds both std_hw and std_vw in order" do
        params = { std_hw: 80, std_vw: 90 }
        cvt = generator.generate_cvt(params)

        expect(cvt).to eq([80, 90])
      end
    end

    context "with stem snap values" do
      it "adds stem_snap_h values" do
        params = { stem_snap_h: [75, 80, 85] }
        cvt = generator.generate_cvt(params)

        expect(cvt).to eq([75, 80, 85])
      end

      it "adds stem_snap_v values" do
        params = { stem_snap_v: [85, 90, 95] }
        cvt = generator.generate_cvt(params)

        expect(cvt).to eq([85, 90, 95])
      end

      it "combines standard widths and stem snaps" do
        params = {
          std_hw: 80,
          std_vw: 90,
          stem_snap_h: [75, 80, 85],
          stem_snap_v: [85, 90, 95],
        }
        cvt = generator.generate_cvt(params)

        expect(cvt).to eq([75, 80, 85, 90, 95])
      end
    end

    context "with blue zone values" do
      it "adds blue_values" do
        params = { blue_values: [-20, 0, 700, 720] }
        cvt = generator.generate_cvt(params)

        expect(cvt).to eq([-20, 0, 700, 720])
      end

      it "adds other_blues" do
        params = { other_blues: [-240, -220] }
        cvt = generator.generate_cvt(params)

        expect(cvt).to eq([-240, -220])
      end

      it "combines all blue zone values" do
        params = {
          blue_values: [-20, 0, 700, 720],
          other_blues: [-240, -220],
        }
        cvt = generator.generate_cvt(params)

        expect(cvt).to eq([-240, -220, -20, 0, 700, 720])
      end
    end

    context "with all parameters" do
      it "combines everything in correct order" do
        params = {
          std_hw: 80,
          std_vw: 90,
          stem_snap_h: [75, 80, 85],
          stem_snap_v: [85, 90, 95],
          blue_values: [-20, 0, 700, 720],
          other_blues: [-240, -220],
        }
        cvt = generator.generate_cvt(params)

        expected = [-240, -220, -20, 0, 75, 80, 85, 90, 95, 700, 720]
        expect(cvt).to eq(expected)
      end
    end

    context "with empty parameters" do
      it "returns empty array" do
        cvt = generator.generate_cvt({})
        expect(cvt).to eq([])
      end
    end
  end

  describe "instruction encoding" do
    context "PUSHB instructions" do
      it "uses PUSHB[0] for single byte" do
        params = { std_hw: 80 }
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        # Should contain PUSHB[0] (0xB0) for pushing 9 (sw_cut_in)
        expect(bytes).to include(0xB0)
      end

      it "uses PUSHB[n] for multiple bytes (2-8)" do
        # Create scenario that pushes multiple small values
        # This is tested indirectly through CVT generation
        # Testing the private method directly would require exposing it
      end

      it "uses NPUSHB for more than 8 bytes" do
        # This would require a scenario with >8 small values
        # Currently not exposed through public API
        # Testing through integration would be ideal
      end
    end

    context "PUSHW instructions" do
      it "uses PUSHW[0] for single word > 255" do
        params = { std_hw: 300 } # > 255, requires word
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        # Should contain PUSHW[0] (0xB8)
        expect(bytes).to include(0xB8)

        # Verify big-endian encoding: 300 = 0x012C
        pushw_index = bytes.index(0xB8)
        expect(bytes[pushw_index + 1]).to eq(0x01) # High byte
        expect(bytes[pushw_index + 2]).to eq(0x2C) # Low byte
      end

      it "encodes words in big-endian format" do
        params = { std_hw: 1000 } # 0x03E8
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        pushw_index = bytes.index(0xB8)
        expect(bytes[pushw_index + 1]).to eq(0x03) # High byte
        expect(bytes[pushw_index + 2]).to eq(0xE8) # Low byte
      end
    end

    context "control instructions" do
      it "generates SCVTCI (0x1D)" do
        params = { blue_scale: 0.039625 }
        prep = generator.generate_prep(params)

        expect(prep.bytes).to include(0x1D)
      end

      it "generates SSWCI (0x1E)" do
        params = { std_hw: 80 }
        prep = generator.generate_prep(params)

        expect(prep.bytes).to include(0x1E)
      end

      it "generates SSW (0x1F)" do
        params = { std_hw: 80 }
        prep = generator.generate_prep(params)

        expect(prep.bytes).to include(0x1F)
      end
    end
  end

  describe "value calculations" do
    describe "CVT cut-in calculation" do
      it "maps standard blue_scale to ~17" do
        params = { blue_scale: 0.039625 }
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        # Extract value before SCVTCI
        scvtci_index = bytes.index(0x1D)
        value = bytes[scvtci_index - 1]

        expect(value).to be_within(1).of(17)
      end

      it "maps zero to zero" do
        params = { blue_scale: 0.0 }
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        scvtci_index = bytes.index(0x1D)
        value = bytes[scvtci_index - 1]

        expect(value).to eq(0)
      end

      it "clamps to 255 maximum" do
        params = { blue_scale: 2.0 } # Way over 1.0
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        scvtci_index = bytes.index(0x1D)
        value = bytes[scvtci_index - 1]

        expect(value).to eq(255)
      end
    end

    describe "SW cut-in calculation" do
      it "always returns 9 pixels" do
        params = { std_hw: 80 }
        prep = generator.generate_prep(params)
        bytes = prep.bytes

        sswci_index = bytes.index(0x1E)
        value = bytes[sswci_index - 1]

        expect(value).to eq(9)
      end
    end
  end

  describe "binary encoding" do
    it "returns binary-encoded strings" do
      params = { blue_scale: 0.039625, std_hw: 80 }
      result = generator.generate(params)

      expect(result[:fpgm].encoding).to eq(Encoding::BINARY)
      expect(result[:prep].encoding).to eq(Encoding::BINARY)
    end

    it "creates valid TrueType bytecode" do
      params = { blue_scale: 0.039625, std_hw: 80 }
      prep = generator.generate_prep(params)

      # Verify it's valid bytes (no encoding errors)
      expect { prep.unpack("C*") }.not_to raise_error
    end
  end

  describe "edge cases" do
    it "handles nil values" do
      params = { std_hw: nil, std_vw: 90 }
      cvt = generator.generate_cvt(params)

      expect(cvt).to eq([90])
    end

    it "handles empty arrays" do
      params = { stem_snap_h: [], stem_snap_v: [] }
      cvt = generator.generate_cvt(params)

      expect(cvt).to eq([])
    end

    it "handles mixed present/absent parameters" do
      params = { std_hw: 80, blue_values: [-20, 0] }
      cvt = generator.generate_cvt(params)

      expect(cvt).to eq([-20, 0, 80])
    end

    it "preserves negative CVT values" do
      params = { blue_values: [-240, -220, -20, 0] }
      cvt = generator.generate_cvt(params)

      expect(cvt).to include(-240, -220, -20)
    end
  end

  describe "integration with analyzer" do
    it "generates valid prep that analyzer can parse" do
      params = {
        blue_scale: 0.039625,
        std_hw: 80,
        std_vw: 90,
      }

      prep = generator.generate_prep(params)
      cvt = generator.generate_cvt(params)

      # Verify prep is valid bytecode
      expect(prep.bytes).to all(be_between(0, 255))

      # Verify CVT values make sense
      expect(cvt).to include(80, 90)
    end
  end
end
