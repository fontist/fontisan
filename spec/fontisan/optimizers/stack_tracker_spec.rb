# frozen_string_literal: true

require "spec_helper"
require "fontisan/optimizers/stack_tracker"

RSpec.describe Fontisan::Optimizers::StackTracker do
  # Helper to encode CFF integer
  def encode_cff_int(value)
    if value >= -107 && value <= 107
      [139 + value].pack("C")
    elsif value >= 108 && value <= 1131
      b0 = 247 + ((value - 108) >> 8)
      b1 = (value - 108) & 0xff
      [b0, b1].pack("C*")
    elsif value >= -1131 && value <= -108
      b0 = 251 - ((value + 108) >> 8)
      b1 = -(value + 108) & 0xff
      [b0, b1].pack("C*")
    else
      # 16-bit encoding
      [28, (value >> 8) & 0xff, value & 0xff].pack("C*")
    end
  end

  describe "#track" do
    it "tracks stack depth for simple operands" do
      # CharString: 10 20 (two operands)
      # 10 = byte 149, 20 = byte 159
      charstring = encode_cff_int(10) + encode_cff_int(20)

      tracker = described_class.new(charstring)
      stack_map = tracker.track

      # Position 0: depth 0
      # Position 1: depth 1 (after first operand)
      # Position 2: depth 2 (after second operand)
      expect(stack_map[0]).to eq(0)
      expect(stack_map[1]).to eq(1)
      expect(stack_map[2]).to eq(2)
    end

    it "tracks stack depth with operators" do
      # CharString: 10 20 rmoveto (two operands, then rmoveto which consumes them)
      # rmoveto (op 21) consumes 2 operands
      charstring = encode_cff_int(10) + encode_cff_int(20) + [21].pack("C")

      tracker = described_class.new(charstring)
      stack_map = tracker.track

      # Position 0: depth 0
      # Position 1: depth 1 (after 10)
      # Position 2: depth 2 (after 20)
      # Position 3: depth 0 (after rmoveto consumes both)
      expect(stack_map[0]).to eq(0)
      expect(stack_map[1]).to eq(1)
      expect(stack_map[2]).to eq(2)
      expect(stack_map[3]).to eq(0)
    end

    it "tracks stack depth with arithmetic operators" do
      # CharString: 10 20 add (10, 20, add operator)
      # add (op 12,10) consumes 2, produces 1
      charstring = encode_cff_int(10) + encode_cff_int(20) + [12, 10].pack("C*")

      tracker = described_class.new(charstring)
      stack_map = tracker.track

      # Position 0: depth 0
      # Position 1: depth 1 (after 10)
      # Position 2: depth 2 (after 20)
      # Position 4: depth 1 (after add: consumes 2, produces 1)
      expect(stack_map[0]).to eq(0)
      expect(stack_map[1]).to eq(1)
      expect(stack_map[2]).to eq(2)
      expect(stack_map[4]).to eq(1)
    end

    it "handles multi-byte numbers correctly" do
      # CharString with 16-bit integer (28, b1, b2)
      charstring = [28, 0x01, 0x00].pack("C*") # 256 encoded as 16-bit

      tracker = described_class.new(charstring)
      stack_map = tracker.track

      # Should have depth 1 after the number
      expect(stack_map[3]).to eq(1)
    end

    it "handles CFF integer ranges" do
      # Small integer (32-246 range): -107 to +107
      # 0 is encoded as byte 139
      charstring = [139].pack("C")

      tracker = described_class.new(charstring)
      stack_map = tracker.track

      expect(stack_map[0]).to eq(0)
      expect(stack_map[1]).to eq(1)
    end
  end

  describe "#stack_neutral?" do
    it "identifies stack-neutral patterns" do
      # Pattern: 10 20 add (push 10, push 20, add)
      # Start depth 0, end depth 1 - NOT stack-neutral
      charstring = encode_cff_int(10) + encode_cff_int(20) + [12,
                                                              10].pack("C*") +
        encode_cff_int(30) + [21].pack("C")

      tracker = described_class.new(charstring)
      tracker.track

      # Pattern from 0 to 4 is NOT neutral (0 -> 1)
      expect(tracker.stack_neutral?(0, 4)).to be false
    end

    it "identifies truly stack-neutral patterns" do
      # Pattern: 10 20 rmoveto - consumes both, neutral
      charstring = encode_cff_int(10) + encode_cff_int(20) + [21].pack("C")

      tracker = described_class.new(charstring)
      tracker.track

      # From position 0 to 3: starts at 0, ends at 0
      expect(tracker.stack_neutral?(0, 3)).to be true
    end

    it "handles patterns that produce net zero stack change" do
      # 10 20 add drop (10, 20, add, drop)
      # Push 2, add (2->1), drop (1->0) = neutral
      charstring = encode_cff_int(10) + encode_cff_int(20) + [12, 10,
                                                              18].pack("C*")

      tracker = described_class.new(charstring)
      tracker.track

      # Should be neutral: 0 -> 0
      expect(tracker.stack_neutral?(0, 5)).to be true
    end
  end

  describe "#depth_at" do
    it "returns stack depth at specified position" do
      charstring = encode_cff_int(10) + encode_cff_int(20) + encode_cff_int(30)

      tracker = described_class.new(charstring)
      tracker.track

      expect(tracker.depth_at(0)).to eq(0)
      expect(tracker.depth_at(1)).to eq(1)
      expect(tracker.depth_at(2)).to eq(2)
      expect(tracker.depth_at(3)).to eq(3)
    end

    it "returns nil for untracked positions" do
      charstring = encode_cff_int(10)

      tracker = described_class.new(charstring)
      tracker.track

      expect(tracker.depth_at(999)).to be_nil
    end
  end

  describe "operator effects" do
    it "correctly handles path operators" do
      # vmoveto (op 4) consumes 1 operand
      charstring = encode_cff_int(50) + [4].pack("C")

      tracker = described_class.new(charstring)
      stack_map = tracker.track

      expect(stack_map[2]).to eq(0) # After vmoveto
    end

    it "correctly handles curve operators" do
      # rrcurveto consumes 6
      charstring = encode_cff_int(10) + encode_cff_int(20) + encode_cff_int(30) +
        encode_cff_int(40) + encode_cff_int(50) + encode_cff_int(60) +
        [8].pack("C")

      tracker = described_class.new(charstring)
      stack_map = tracker.track

      expect(stack_map[0]).to eq(0)
      expect(stack_map[6]).to eq(6)
      expect(stack_map[7]).to eq(0) # After rrcurveto
    end

    it "handles endchar operator" do
      # endchar (op 14) consumes 0
      charstring = encode_cff_int(10) + [14].pack("C")

      tracker = described_class.new(charstring)
      stack_map = tracker.track

      expect(stack_map[1]).to eq(1)
      expect(stack_map[2]).to eq(1) # endchar doesn't change stack
    end
  end

  describe "edge cases" do
    it "handles empty CharString" do
      charstring = "".b

      tracker = described_class.new(charstring)
      stack_map = tracker.track

      expect(stack_map[0]).to eq(0)
    end

    it "handles CharString with only operators" do
      charstring = [14].pack("C") # just endchar

      tracker = described_class.new(charstring)
      stack_map = tracker.track

      expect(stack_map[0]).to eq(0)
      expect(stack_map[1]).to eq(0)
    end

    it "prevents negative stack depth" do
      # Try to consume from empty stack
      charstring = [18].pack("C") # drop with nothing on stack

      tracker = described_class.new(charstring)
      stack_map = tracker.track

      # Should not go negative
      expect(stack_map[1]).to eq(0)
    end
  end
end
