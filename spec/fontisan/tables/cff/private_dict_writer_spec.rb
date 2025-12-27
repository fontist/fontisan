# frozen_string_literal: true

require "spec_helper"
require "fontisan/tables/cff/private_dict_writer"

RSpec.describe Fontisan::Tables::Cff::PrivateDictWriter do
  describe "#initialize" do
    it "initializes with nil" do
      writer = described_class.new
      expect(writer.serialize).to eq("".b)
    end

    it "initializes with empty params" do
      writer = described_class.new(nil)
      expect(writer.size).to eq(0)
    end
  end

  describe "#update_hints" do
    context "with valid blue_values" do
      it "updates blue_values with 2 values" do
        writer = described_class.new
        writer.update_hints(blue_values: [-15, 0])
        expect(writer.serialize).not_to be_empty
      end

      it "updates blue_values with 14 values (max)" do
        writer = described_class.new
        writer.update_hints(blue_values: [-15, 0, 721, 736, 470, 485, 520, 535, 560, 575, 610, 625, 640, 655])
        expect(writer.serialize).not_to be_empty
      end
    end

    context "with invalid blue_values" do
      it "rejects blue_values with >14 values" do
        writer = described_class.new
        expect do
          writer.update_hints(blue_values: Array.new(16, 0))
        end.to raise_error(ArgumentError, /blue_values too long/)
      end

      it "rejects odd-length blue_values" do
        writer = described_class.new
        expect do
          writer.update_hints(blue_values: [1, 2, 3])
        end.to raise_error(ArgumentError, /blue_values must be pairs/)
      end

      it "rejects non-array blue_values" do
        writer = described_class.new
        expect do
          writer.update_hints(blue_values: 100)
        end.to raise_error(ArgumentError, /blue_values invalid/)
      end
    end

    context "with stem widths" do
      it "updates std_hw" do
        writer = described_class.new
        writer.update_hints(std_hw: 70)
        expect(writer.size).to be > 0
      end

      it "updates std_vw" do
        writer = described_class.new
        writer.update_hints(std_vw: 85)
        expect(writer.size).to be > 0
      end

      it "rejects negative std_hw" do
        writer = described_class.new
        expect do
          writer.update_hints(std_hw: -10)
        end.to raise_error(ArgumentError, /std_hw negative/)
      end

      it "rejects negative std_vw" do
        writer = described_class.new
        expect do
          writer.update_hints(std_vw: -5)
        end.to raise_error(ArgumentError, /std_vw negative/)
      end
    end

    context "with stem snaps" do
      it "updates stem_snap_h" do
        writer = described_class.new
        writer.update_hints(stem_snap_h: [70, 75, 80])
        expect(writer.size).to be > 0
      end

      it "updates stem_snap_v" do
        writer = described_class.new
        writer.update_hints(stem_snap_v: [85, 90])
        expect(writer.size).to be > 0
      end

      it "accepts max 12 values for stem_snap_h" do
        writer = described_class.new
        writer.update_hints(stem_snap_h: Array.new(12, 70))
        expect(writer.size).to be > 0
      end

      it "rejects >12 values for stem_snap_h" do
        writer = described_class.new
        expect do
          writer.update_hints(stem_snap_h: Array.new(13, 70))
        end.to raise_error(ArgumentError, /stem_snap_h too long/)
      end

      it "rejects >12 values for stem_snap_v" do
        writer = described_class.new
        expect do
          writer.update_hints(stem_snap_v: Array.new(13, 85))
        end.to raise_error(ArgumentError, /stem_snap_v too long/)
      end
    end

    context "with other_blues" do
      it "updates other_blues with pairs" do
        writer = described_class.new
        writer.update_hints(other_blues: [-250, -240, -250, -240])
        expect(writer.size).to be > 0
      end

      it "accepts max 10 values" do
        writer = described_class.new
        writer.update_hints(other_blues: Array.new(10, 0))
        expect(writer.size).to be > 0
      end

      it "rejects >10 values" do
        writer = described_class.new
        expect do
          writer.update_hints(other_blues: Array.new(12, 0))
        end.to raise_error(ArgumentError, /other_blues too long/)
      end

      it "rejects odd-length other_blues" do
        writer = described_class.new
        expect do
          writer.update_hints(other_blues: [1, 2, 3])
        end.to raise_error(ArgumentError, /other_blues must be pairs/)
      end
    end

    context "with blue_scale" do
      it "updates blue_scale with positive value" do
        writer = described_class.new
        writer.update_hints(blue_scale: 0.039625)
        expect(writer.size).to be > 0
      end

      it "rejects zero blue_scale" do
        writer = described_class.new
        expect do
          writer.update_hints(blue_scale: 0)
        end.to raise_error(ArgumentError, /blue_scale not positive/)
      end

      it "rejects negative blue_scale" do
        writer = described_class.new
        expect do
          writer.update_hints(blue_scale: -0.5)
        end.to raise_error(ArgumentError, /blue_scale not positive/)
      end
    end

    context "with language_group" do
      it "accepts language_group 0" do
        writer = described_class.new
        writer.update_hints(language_group: 0)
        expect(writer.size).to be > 0
      end

      it "accepts language_group 1" do
        writer = described_class.new
        writer.update_hints(language_group: 1)
        expect(writer.size).to be > 0
      end

      it "rejects language_group 2" do
        writer = described_class.new
        expect do
          writer.update_hints(language_group: 2)
        end.to raise_error(ArgumentError, /language_group must be 0 or 1/)
      end
    end

    context "with multiple parameters" do
      it "updates multiple hint params at once" do
        writer = described_class.new
        writer.update_hints(
          blue_values: [-15, 0, 721, 736],
          other_blues: [-250, -240],
          std_hw: 70,
          std_vw: 85,
          stem_snap_h: [70, 75],
          blue_scale: 0.039625
        )
        expect(writer.size).to be > 20
      end
    end
  end

  describe "#serialize" do
    it "serializes to binary" do
      writer = described_class.new
      writer.update_hints(std_hw: 70)
      result = writer.serialize
      expect(result.encoding).to eq(Encoding::BINARY)
    end

    it "produces empty binary for no params" do
      writer = described_class.new
      expect(writer.serialize).to eq("".b)
    end

    it "produces parseable DICT" do
      writer = described_class.new
      writer.update_hints(blue_values: [-15, 0], std_hw: 70)
      result = writer.serialize
      expect(result).to be_a(String)
      expect(result.bytesize).to be > 0
    end
  end

  describe "#size" do
    it "returns correct byte size" do
      writer = described_class.new
      writer.update_hints(std_hw: 70)
      expect(writer.size).to eq(writer.serialize.bytesize)
    end

    it "returns 0 for empty params" do
      writer = described_class.new
      expect(writer.size).to eq(0)
    end

    it "increases with more params" do
      writer = described_class.new
      writer.update_hints(std_hw: 70)
      size1 = writer.size

      writer.update_hints(std_vw: 85)
      size2 = writer.size

      expect(size2).to be > size1
    end
  end

  describe "family hint parameters" do
    it "updates family_blues" do
      writer = described_class.new
      writer.update_hints(family_blues: [-15, 0, 721, 736])
      expect(writer.size).to be > 0
    end

    it "updates family_other_blues" do
      writer = described_class.new
      writer.update_hints(family_other_blues: [-250, -240])
      expect(writer.size).to be > 0
    end

    it "validates family_blues pairs" do
      writer = described_class.new
      expect do
        writer.update_hints(family_blues: [1, 2, 3])
      end.to raise_error(ArgumentError, /family_blues must be pairs/)
    end

    it "validates family_other_blues max length" do
      writer = described_class.new
      expect do
        writer.update_hints(family_other_blues: Array.new(12, 0))
      end.to raise_error(ArgumentError, /family_other_blues too long/)
    end
  end
end