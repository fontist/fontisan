# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cff/hint_operation_injector"
require "fontisan/models/hint"

RSpec.describe Fontisan::Tables::Cff::HintOperationInjector do
  let(:injector) { described_class.new }

  describe "#inject" do
    context "with no hints" do
      it "returns original operations unchanged when hints array is empty" do
        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([], operations)
        expect(result).to eq(operations)
      end

      it "returns original operations unchanged when hints is nil" do
        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject(nil, operations)
        expect(result).to eq(operations)
      end
    end

    context "with stem hints" do
      it "injects horizontal stem hint before moveto" do
        hint = Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal },
        )

        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :rlineto, operands: [50, 0],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result.length).to eq(4)
        expect(result[0][:name]).to eq(:hstem)
        expect(result[0][:operands]).to eq([100, 50])
        expect(result[1][:name]).to eq(:rmoveto)
      end

      it "injects vertical stem hint before moveto" do
        hint = Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 200, width: 60, orientation: :vertical },
        )

        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result[0][:name]).to eq(:vstem)
        expect(result[0][:operands]).to eq([200, 60])
        expect(result[1][:name]).to eq(:rmoveto)
      end

      it "injects multiple stem hints" do
        hints = [
          Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 100, width: 50, orientation: :horizontal },
          ),
          Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 200, width: 60, orientation: :vertical },
          ),
        ]

        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject(hints, operations)

        expect(result.length).to eq(4)
        expect(result[0][:name]).to eq(:hstem)
        expect(result[1][:name]).to eq(:vstem)
        expect(result[2][:name]).to eq(:rmoveto)
      end

      it "updates stem count correctly" do
        hints = [
          Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 100, width: 50, orientation: :horizontal },
          ),
          Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 200, width: 60, orientation: :vertical },
          ),
        ]

        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        injector.inject(hints, operations)
        expect(injector.stem_count).to eq(2)
      end
    end

    context "with hintmask" do
      it "injects hintmask operation with mask data" do
        hint = Fontisan::Models::Hint.new(
          type: :hint_replacement,
          data: { mask: [0b11000000] },
        )

        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result[0][:name]).to eq(:hintmask)
        expect(result[0][:operands]).to eq([])
        expect(result[0][:hint_data]).to eq([0b11000000].pack("C*"))
        expect(result[1][:name]).to eq(:rmoveto)
      end

      it "handles string mask data" do
        hint = Fontisan::Models::Hint.new(
          type: :hint_replacement,
          data: { mask: "\xC0" },
        )

        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result[0][:name]).to eq(:hintmask)
        expect(result[0][:hint_data]).to eq("\xC0")
      end

      it "handles empty mask data" do
        hint = Fontisan::Models::Hint.new(
          type: :hint_replacement,
          data: { mask: [] },
        )

        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result[0][:name]).to eq(:hintmask)
        expect(result[0][:hint_data]).to eq("")
      end
    end

    context "with cntrmask" do
      it "injects cntrmask operation with zone data" do
        hint = Fontisan::Models::Hint.new(
          type: :counter,
          data: { zones: [0b10100000] },
        )

        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result[0][:name]).to eq(:cntrmask)
        expect(result[0][:operands]).to eq([])
        expect(result[0][:hint_data]).to eq([0b10100000].pack("C*"))
        expect(result[1][:name]).to eq(:rmoveto)
      end
    end

    context "with mixed hint types" do
      it "injects stems then hintmask in correct order" do
        hints = [
          Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 100, width: 50, orientation: :horizontal },
          ),
          Fontisan::Models::Hint.new(
            type: :hint_replacement,
            data: { mask: [0b11000000] },
          ),
        ]

        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject(hints, operations)

        expect(result.length).to eq(4)
        expect(result[0][:name]).to eq(:hstem)
        expect(result[1][:name]).to eq(:hintmask)
        expect(result[2][:name]).to eq(:rmoveto)
      end
    end

    context "with different path operators" do
      it "injects before hmoveto" do
        hint = Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal },
        )

        operations = [
          { type: :operator, name: :hmoveto, operands: [100], hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result[0][:name]).to eq(:hstem)
        expect(result[1][:name]).to eq(:hmoveto)
      end

      it "injects before vmoveto" do
        hint = Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal },
        )

        operations = [
          { type: :operator, name: :vmoveto, operands: [200], hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result[0][:name]).to eq(:hstem)
        expect(result[1][:name]).to eq(:vmoveto)
      end

      it "injects before rlineto if no moveto" do
        hint = Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal },
        )

        operations = [
          { type: :operator, name: :rlineto, operands: [50, 0],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result[0][:name]).to eq(:hstem)
        expect(result[1][:name]).to eq(:rlineto)
      end

      it "injects before hlineto" do
        hint = Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal },
        )

        operations = [
          { type: :operator, name: :hlineto, operands: [50], hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result[0][:name]).to eq(:hstem)
        expect(result[1][:name]).to eq(:hlineto)
      end

      it "injects before vlineto" do
        hint = Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal },
        )

        operations = [
          { type: :operator, name: :vlineto, operands: [50], hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result[0][:name]).to eq(:hstem)
        expect(result[1][:name]).to eq(:vlineto)
      end

      it "injects before rrcurveto" do
        hint = Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal },
        )

        operations = [
          { type: :operator, name: :rrcurveto,
            operands: [10, 20, 30, 40, 50, 60], hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result[0][:name]).to eq(:hstem)
        expect(result[1][:name]).to eq(:rrcurveto)
      end
    end

    context "with no path operators" do
      it "injects before endchar when only endchar present" do
        hint = Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal },
        )

        operations = [
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result[0][:name]).to eq(:hstem)
        expect(result[1][:name]).to eq(:endchar)
      end

      it "injects at start when operations empty" do
        hint = Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal },
        )

        operations = []

        result = injector.inject([hint], operations)

        expect(result.length).to eq(1)
        expect(result[0][:name]).to eq(:hstem)
      end
    end

    context "with complex CharStrings" do
      it "injects hints before first moveto in multi-path glyph" do
        hint = Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal },
        )

        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :rlineto, operands: [50, 0],
            hint_data: nil },
          { type: :operator, name: :rmoveto, operands: [10, 10],
            hint_data: nil },
          { type: :operator, name: :rlineto, operands: [30, 0],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result[0][:name]).to eq(:hstem)
        expect(result[1][:name]).to eq(:rmoveto)
        expect(result[2][:name]).to eq(:rlineto)
      end

      it "preserves original operations after injection point" do
        hint = Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal },
        )

        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :rlineto, operands: [50, 0],
            hint_data: nil },
          { type: :operator, name: :rrcurveto,
            operands: [10, 20, 30, 40, 50, 60], hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        result = injector.inject([hint], operations)

        expect(result[1]).to eq(operations[0])
        expect(result[2]).to eq(operations[1])
        expect(result[3]).to eq(operations[2])
        expect(result[4]).to eq(operations[3])
      end
    end

    context "stem count tracking" do
      it "counts single stem" do
        hint = Fontisan::Models::Hint.new(
          type: :stem,
          data: { position: 100, width: 50, orientation: :horizontal },
        )

        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        injector.inject([hint], operations)
        expect(injector.stem_count).to eq(1)
      end

      it "counts multiple stems" do
        hints = [
          Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 100, width: 50, orientation: :horizontal },
          ),
          Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 200, width: 60, orientation: :vertical },
          ),
          Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 300, width: 70, orientation: :horizontal },
          ),
        ]

        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        injector.inject(hints, operations)
        expect(injector.stem_count).to eq(3)
      end

      it "does not count hintmask in stem count" do
        hints = [
          Fontisan::Models::Hint.new(
            type: :stem,
            data: { position: 100, width: 50, orientation: :horizontal },
          ),
          Fontisan::Models::Hint.new(
            type: :hint_replacement,
            data: { mask: [0b11000000] },
          ),
        ]

        operations = [
          { type: :operator, name: :rmoveto, operands: [100, 200],
            hint_data: nil },
          { type: :operator, name: :endchar, operands: [], hint_data: nil },
        ]

        injector.inject(hints, operations)
        expect(injector.stem_count).to eq(1)
      end
    end
  end
end
