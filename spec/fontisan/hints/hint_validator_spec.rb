# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Hints::HintValidator do
  subject(:validator) { described_class.new }

  describe "#validate_truetype_instructions" do
    context "with valid instructions" do
      it "accepts empty instructions" do
        result = validator.validate_truetype_instructions("")
        
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end

      it "accepts nil instructions" do
        result = validator.validate_truetype_instructions(nil)
        
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end

      it "accepts PUSHB instruction" do
        # PUSHB[0] 17
        instructions = [0xB0, 17].pack("C*")
        result = validator.validate_truetype_instructions(instructions)
        
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end

      it "accepts PUSHW instruction" do
        # PUSHW[0] 300 (0x012C)
        instructions = [0xB8, 0x01, 0x2C].pack("C*")
        result = validator.validate_truetype_instructions(instructions)
        
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end

      it "accepts NPUSHB instruction" do
        # NPUSHB 3, values: 10, 20, 30
        instructions = [0x40, 3, 10, 20, 30].pack("C*")
        result = validator.validate_truetype_instructions(instructions)
        
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end

      it "accepts NPUSHW instruction" do
        # NPUSHW 2, values: 300, 400
        instructions = [0x41, 2, 0x01, 0x2C, 0x01, 0x90].pack("C*")
        result = validator.validate_truetype_instructions(instructions)
        
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end

      it "accepts stack-neutral instruction sequence" do
        # PUSHB[0] 17, SCVTCI (push 1, pop 1 = neutral)
        instructions = [0xB0, 17, 0x1D].pack("C*")
        result = validator.validate_truetype_instructions(instructions)
        
        expect(result[:valid]).to be true
        expect(result[:warnings]).to be_empty
      end
    end

    context "with invalid instructions" do
      it "detects truncated NPUSHB" do
        # NPUSHB says 10 bytes but only 3 provided
        instructions = [0x40, 10, 1, 2, 3].pack("C*")
        result = validator.validate_truetype_instructions(instructions)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/NPUSHB.*Not enough bytes/))
      end

      it "detects truncated NPUSHW" do
        # NPUSHW says 5 words but only 2 bytes provided
        instructions = [0x41, 5, 0x01, 0x2C].pack("C*")
        result = validator.validate_truetype_instructions(instructions)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/NPUSHW.*Not enough bytes/))
      end

      it "detects truncated PUSHB" do
        # PUSHB[2] needs 3 bytes but only 1 provided
        instructions = [0xB2, 10].pack("C*")
        result = validator.validate_truetype_instructions(instructions)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/PUSHB.*Not enough bytes/))
      end

      it "detects truncated PUSHW" do
        # PUSHW[1] needs 4 bytes but only 2 provided
        instructions = [0xB9, 0x01, 0x2C].pack("C*")
        result = validator.validate_truetype_instructions(instructions)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/PUSHW.*Not enough bytes/))
      end

      it "detects stack underflow for SCVTCI" do
        # SCVTCI without value on stack
        instructions = [0x1D].pack("C*")
        result = validator.validate_truetype_instructions(instructions)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/SCVTCI.*Stack underflow/))
      end

      it "detects stack underflow for WCVTP" do
        # WCVTP needs 2 values but stack is empty
        instructions = [0x44].pack("C*")
        result = validator.validate_truetype_instructions(instructions)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/WCVTP.*Stack underflow/))
      end
    end

    context "with warnings" do
      it "warns about unknown opcodes" do
        # 0xFF is not a standard opcode
        instructions = [0xFF].pack("C*")
        result = validator.validate_truetype_instructions(instructions)
        
        expect(result[:warnings]).to include(a_string_matching(/Unknown opcode.*0xFF/))
      end

      it "warns about non-neutral stack" do
        # PUSHB[0] 17 (push 1, no pop = not neutral)
        instructions = [0xB0, 17].pack("C*")
        result = validator.validate_truetype_instructions(instructions)
        
        expect(result[:warnings]).to include(a_string_matching(/Stack not neutral.*1 value/))
      end

      it "warns about multiple values on stack" do
        # PUSHB[2] 10, 20, 30 (push 3, no pops = not neutral)
        instructions = [0xB2, 10, 20, 30].pack("C*")
        result = validator.validate_truetype_instructions(instructions)
        
        expect(result[:warnings]).to include(a_string_matching(/Stack not neutral.*3 value/))
      end
    end

    context "error handling" do
      it "catches exceptions during validation" do
        # This should not raise an exception
        expect {
          validator.validate_truetype_instructions("invalid\x00binary\xFF")
        }.not_to raise_error
      end
    end
  end

  describe "#validate_postscript_hints" do
    context "with valid parameters" do
      it "accepts empty hints" do
        result = validator.validate_postscript_hints({})
        
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end

      it "accepts valid blue_values (even count, <= 14)" do
        hints = { blue_values: [-20, 0, 700, 720] }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be true
      end

      it "accepts maximum blue_values (14 values)" do
        hints = { blue_values: Array.new(14) { |i| i * 100 } }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be true
      end

      it "accepts valid other_blues (even count, <= 10)" do
        hints = { other_blues: [-240, -220] }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be true
      end

      it "accepts positive stem widths" do
        hints = { std_hw: 80, std_vw: 90 }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be true
      end

      it "accepts valid stem_snap arrays (<= 12)" do
        hints = { stem_snap_h: [75, 80, 85], stem_snap_v: [85, 90, 95] }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be true
      end

      it "accepts valid blue_scale" do
        hints = { blue_scale: 0.039625 }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be true
      end

      it "accepts valid language_group" do
        hints = { language_group: 0 }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be true
      end
    end

    context "with invalid blue_values" do
      it "rejects blue_values with odd count" do
        hints = { blue_values: [-20, 0, 700] } # 3 values (odd)
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/blue_values must be pairs/))
      end

      it "rejects blue_values exceeding 14" do
        hints = { blue_values: Array.new(16) { |i| i * 100 } }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/blue_values exceeds maximum/))
      end
    end

    context "with invalid other_blues" do
      it "rejects other_blues with odd count" do
        hints = { other_blues: [-240, -220, -200] } # 3 values (odd)
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/other_blues must be pairs/))
      end

      it "rejects other_blues exceeding 10" do
        hints = { other_blues: Array.new(12) { |i| -i * 100 } }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/other_blues exceeds maximum/))
      end
    end

    context "with invalid stem widths" do
      it "rejects negative std_hw" do
        hints = { std_hw: -80 }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/std_hw must be positive/))
      end

      it "rejects zero std_hw" do
        hints = { std_hw: 0 }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/std_hw must be positive/))
      end

      it "rejects negative std_vw" do
        hints = { std_vw: -90 }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/std_vw must be positive/))
      end
    end

    context "with invalid stem_snap values" do
      it "rejects stem_snap_h exceeding 12" do
        hints = { stem_snap_h: Array.new(13) { |i| 70 + i } }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/stem_snap_h exceeds maximum/))
      end

      it "rejects stem_snap_v exceeding 12" do
        hints = { stem_snap_v: Array.new(13) { |i| 80 + i } }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/stem_snap_v exceeds maximum/))
      end

      it "warns about non-positive stem_snap_h values" do
        hints = { stem_snap_h: [75, -10, 85] }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:warnings]).to include(a_string_matching(/stem_snap_h contains non-positive/))
      end
    end

    context "with invalid blue_scale" do
      it "rejects zero blue_scale" do
        hints = { blue_scale: 0.0 }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/blue_scale must be positive/))
      end

      it "rejects negative blue_scale" do
        hints = { blue_scale: -0.5 }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/blue_scale must be positive/))
      end

      it "warns about unusually large blue_scale" do
        hints = { blue_scale: 2.0 }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:warnings]).to include(a_string_matching(/blue_scale unusually large/))
      end
    end

    context "with invalid language_group" do
      it "rejects invalid language_group" do
        hints = { language_group: 5 }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(a_string_matching(/language_group must be 0.*or 1/))
      end

      it "accepts language_group 0 (Latin)" do
        hints = { language_group: 0 }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be true
      end

      it "accepts language_group 1 (CJK)" do
        hints = { language_group: 1 }
        result = validator.validate_postscript_hints(hints)
        
        expect(result[:valid]).to be true
      end
    end
  end

  describe "#validate_stack_neutrality" do
    it "accepts empty instructions" do
      result = validator.validate_stack_neutrality("")
      
      expect(result[:neutral]).to be true
      expect(result[:stack_depth]).to eq(0)
    end

    it "accepts nil instructions" do
      result = validator.validate_stack_neutrality(nil)
      
      expect(result[:neutral]).to be true
      expect(result[:stack_depth]).to eq(0)
    end

    it "accepts neutral instruction sequence" do
      # PUSHB[0] 17, SCVTCI (push 1, pop 1)
      instructions = [0xB0, 17, 0x1D].pack("C*")
      result = validator.validate_stack_neutrality(instructions)
      
      expect(result[:neutral]).to be true
      expect(result[:stack_depth]).to eq(0)
    end

    it "detects non-neutral sequence (values remaining)" do
      # PUSHB[0] 17 (push 1, no pop)
      instructions = [0xB0, 17].pack("C*")
      result = validator.validate_stack_neutrality(instructions)
      
      expect(result[:neutral]).to be false
      expect(result[:stack_depth]).to eq(1)
    end

    it "detects non-neutral sequence (multiple values)" do
      # PUSHB[2] 10, 20, 30 (push 3, no pops)
      instructions = [0xB2, 10, 20, 30].pack("C*")
      result = validator.validate_stack_neutrality(instructions)
      
      expect(result[:neutral]).to be false
      expect(result[:stack_depth]).to eq(3)
    end

    it "handles complex neutral sequence" do
      # PUSHB[0] 17, SCVTCI, PUSHB[0] 9, SSWCI, PUSHB[0] 80, SSW
      # (push 1, pop 1, push 1, pop 1, push 1, pop 1 = neutral)
      instructions = [0xB0, 17, 0x1D, 0xB0, 9, 0x1E, 0xB0, 80, 0x1F].pack("C*")
      result = validator.validate_stack_neutrality(instructions)
      
      expect(result[:neutral]).to be true
      expect(result[:stack_depth]).to eq(0)
    end

    it "handles errors gracefully" do
      # Malformed instructions
      expect {
        validator.validate_stack_neutrality("invalid\xFF")
      }.not_to raise_error
    end
  end
end