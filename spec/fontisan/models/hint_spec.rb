# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Models::Hint do
  describe "#to_truetype" do
    context "with stem hints" do
      it "converts vertical stem hints to TrueType instructions" do
        hint = described_class.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical }
        )

        instructions = hint.to_truetype
        expect(instructions).to be_an(Array)
        expect(instructions).not_to be_empty
        expect(instructions).to include(0x2E, 0xC0) # MDAP, MDRP
      end

      it "converts horizontal stem hints to TrueType instructions" do
        hint = described_class.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal }
        )

        instructions = hint.to_truetype
        expect(instructions).to be_an(Array)
        expect(instructions).not_to be_empty
        expect(instructions).to include(0x2F, 0xC0) # MDAP, MDRP
      end
    end

    context "with stem3 hints" do
      it "converts stem3 hints to multiple TrueType instruction pairs" do
        hint = described_class.new(
          type: :stem3,
          data: {
            stems: [
              { position: 100, width: 50 },
              { position: 200, width: 50 },
              { position: 300, width: 50 }
            ],
            orientation: :vertical
          }
        )

        instructions = hint.to_truetype
        expect(instructions).to be_an(Array)
        # Should have 2 instructions per stem (MDAP + MDRP)
        expect(instructions.length).to eq(6)
      end
    end

    context "with flex hints" do
      it "returns empty array for flex hints" do
        hint = described_class.new(
          type: :flex,
          data: { points: [] }
        )

        instructions = hint.to_truetype
        expect(instructions).to eq([])
      end
    end

    context "with counter hints" do
      it "returns empty array for counter hints" do
        hint = described_class.new(
          type: :counter,
          data: { zones: [] }
        )

        instructions = hint.to_truetype
        expect(instructions).to eq([])
      end
    end

    context "with hint_replacement hints" do
      it "returns empty array for hintmask" do
        hint = described_class.new(
          type: :hint_replacement,
          data: { mask: [0xFF, 0x00] }
        )

        instructions = hint.to_truetype
        expect(instructions).to eq([])
      end
    end

    context "with delta hints" do
      it "preserves TrueType delta instructions" do
        hint = described_class.new(
          type: :delta,
          data: { instructions: [0x5D, 0x01] }
        )

        instructions = hint.to_truetype
        expect(instructions).to eq([0x5D, 0x01])
      end
    end

    context "with interpolate hints" do
      it "converts to IUP[y] for y-axis" do
        hint = described_class.new(
          type: :interpolate,
          data: { axis: :y }
        )

        instructions = hint.to_truetype
        expect(instructions).to eq([0x30])
      end

      it "converts to IUP[x] for x-axis" do
        hint = described_class.new(
          type: :interpolate,
          data: { axis: :x }
        )

        instructions = hint.to_truetype
        expect(instructions).to eq([0x31])
      end
    end

    context "with align hints" do
      it "converts to ALIGNRP instruction" do
        hint = described_class.new(
          type: :align,
          data: {}
        )

        instructions = hint.to_truetype
        expect(instructions).to eq([0x3C])
      end
    end

    context "with error handling" do
      it "returns empty array on conversion error" do
        hint = described_class.new(
          type: :stem,
          data: nil # Invalid data
        )

        expect { hint.to_truetype }.not_to raise_error
        expect(hint.to_truetype).to eq([])
      end
    end
  end

  describe "#to_postscript" do
    context "with stem hints" do
      it "converts vertical stem to vstem operator" do
        hint = described_class.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :vertical }
        )

        ps_data = hint.to_postscript
        expect(ps_data).to be_a(Hash)
        expect(ps_data[:operator]).to eq(:vstem)
        expect(ps_data[:args]).to eq([100, 50])
      end

      it "converts horizontal stem to hstem operator" do
        hint = described_class.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal }
        )

        ps_data = hint.to_postscript
        expect(ps_data).to be_a(Hash)
        expect(ps_data[:operator]).to eq(:hstem)
        expect(ps_data[:args]).to eq([100, 50])
      end
    end

    context "with stem3 hints" do
      it "converts stem3 to vstem3 operator" do
        hint = described_class.new(
          type: :stem3,
          data: {
            stems: [
              { position: 100, width: 50 },
              { position: 200, width: 50 }
            ],
            orientation: :vertical
          }
        )

        ps_data = hint.to_postscript
        expect(ps_data).to be_a(Hash)
        expect(ps_data[:operator]).to eq(:vstem3)
        expect(ps_data[:args]).to eq([100, 50, 200, 50])
      end
    end

    context "with flex hints" do
      it "converts flex to flex operator with points" do
        hint = described_class.new(
          type: :flex,
          data: {
            points: [
              { x: 100, y: 200 },
              { x: 150, y: 250 }
            ]
          }
        )

        ps_data = hint.to_postscript
        expect(ps_data).to be_a(Hash)
        expect(ps_data[:operator]).to eq(:flex)
        expect(ps_data[:args]).to eq([100, 200, 150, 250])
      end
    end

    context "with counter hints" do
      it "converts counter to counter operator" do
        hint = described_class.new(
          type: :counter,
          data: { zones: [100, 200] }
        )

        ps_data = hint.to_postscript
        expect(ps_data).to be_a(Hash)
        expect(ps_data[:operator]).to eq(:counter)
        expect(ps_data[:args]).to eq([100, 200])
      end
    end

    context "with hint_replacement hints" do
      it "converts to hintmask operator" do
        hint = described_class.new(
          type: :hint_replacement,
          data: { mask: [0xFF, 0x00] }
        )

        ps_data = hint.to_postscript
        expect(ps_data).to be_a(Hash)
        expect(ps_data[:operator]).to eq(:hintmask)
        expect(ps_data[:args]).to eq([0xFF, 0x00])
      end
    end

    context "with TrueType-specific hints" do
      it "approximates delta hints as stem" do
        hint = described_class.new(
          type: :delta,
          data: { position: 100, width: 50 }
        )

        ps_data = hint.to_postscript
        expect(ps_data).to be_a(Hash)
        expect(ps_data[:operator]).to eq(:vstem)
      end

      it "approximates interpolate hints as stem" do
        hint = described_class.new(
          type: :interpolate,
          data: { position: 100, width: 50 }
        )

        ps_data = hint.to_postscript
        expect(ps_data).to be_a(Hash)
        expect(ps_data[:operator]).to eq(:vstem)
      end
    end

    context "with error handling" do
      it "returns empty hash on conversion error" do
        hint = described_class.new(
          type: :stem,
          data: nil # Invalid data
        )

        expect { hint.to_postscript }.not_to raise_error
        expect(hint.to_postscript).to eq({})
      end
    end
  end

  describe "#compatible_with?" do
    context "with truetype format" do
      it "returns true for stem hints" do
        hint = described_class.new(type: :stem, data: {})
        expect(hint.compatible_with?(:truetype)).to be true
      end

      it "returns true for flex hints" do
        hint = described_class.new(type: :flex, data: {})
        expect(hint.compatible_with?(:truetype)).to be true
      end

      it "returns true for counter hints" do
        hint = described_class.new(type: :counter, data: {})
        expect(hint.compatible_with?(:truetype)).to be true
      end

      it "returns true for delta hints" do
        hint = described_class.new(type: :delta, data: {})
        expect(hint.compatible_with?(:truetype)).to be true
      end

      it "returns false for stem3 hints" do
        hint = described_class.new(type: :stem3, data: {})
        expect(hint.compatible_with?(:truetype)).to be false
      end
    end

    context "with postscript format" do
      it "returns true for stem hints" do
        hint = described_class.new(type: :stem, data: {})
        expect(hint.compatible_with?(:postscript)).to be true
      end

      it "returns true for stem3 hints" do
        hint = described_class.new(type: :stem3, data: {})
        expect(hint.compatible_with?(:postscript)).to be true
      end

      it "returns true for flex hints" do
        hint = described_class.new(type: :flex, data: {})
        expect(hint.compatible_with?(:postscript)).to be true
      end

      it "returns false for delta hints" do
        hint = described_class.new(type: :delta, data: {})
        expect(hint.compatible_with?(:postscript)).to be false
      end
    end
  end
end