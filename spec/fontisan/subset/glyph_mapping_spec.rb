# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Subset::GlyphMapping do
  describe "initialization" do
    context "compact mode (default)" do
      it "creates mapping with sequential new IDs" do
        mapping = described_class.new([0, 5, 10, 15])

        expect(mapping.new_id(0)).to eq(0)
        expect(mapping.new_id(5)).to eq(1)
        expect(mapping.new_id(10)).to eq(2)
        expect(mapping.new_id(15)).to eq(3)
      end

      it "handles unsorted input" do
        mapping = described_class.new([15, 5, 0, 10])

        expect(mapping.new_id(0)).to eq(0)
        expect(mapping.new_id(5)).to eq(1)
        expect(mapping.new_id(10)).to eq(2)
        expect(mapping.new_id(15)).to eq(3)
      end

      it "handles duplicate IDs" do
        mapping = described_class.new([0, 5, 5, 10])

        expect(mapping.size).to eq(3)
        expect(mapping.new_id(5)).to eq(1)
      end

      it "creates compact mapping" do
        mapping = described_class.new([0, 100, 200])

        expect(mapping.size).to eq(3)
        expect(mapping.new_id(100)).to eq(1)
        expect(mapping.new_id(200)).to eq(2)
      end
    end

    context "retain GID mode" do
      it "preserves original glyph IDs" do
        mapping = described_class.new([0, 5, 10, 15], retain_gids: true)

        expect(mapping.new_id(0)).to eq(0)
        expect(mapping.new_id(5)).to eq(5)
        expect(mapping.new_id(10)).to eq(10)
        expect(mapping.new_id(15)).to eq(15)
      end

      it "includes empty slots for removed glyphs" do
        mapping = described_class.new([0, 5, 10], retain_gids: true)

        # Size includes all slots from 0 to max ID
        expect(mapping.size).to eq(11) # 0..10
      end

      it "handles sparse glyph IDs" do
        mapping = described_class.new([0, 100, 200], retain_gids: true)

        expect(mapping.new_id(0)).to eq(0)
        expect(mapping.new_id(100)).to eq(100)
        expect(mapping.new_id(200)).to eq(200)
        expect(mapping.size).to eq(201) # 0..200
      end
    end
  end

  describe "#new_id" do
    it "returns new GID for old GID" do
      mapping = described_class.new([0, 5, 10])

      expect(mapping.new_id(5)).to eq(1)
    end

    it "returns nil for unmapped old GID" do
      mapping = described_class.new([0, 5, 10])

      expect(mapping.new_id(99)).to be_nil
    end

    it "handles GID 0 (notdef)" do
      mapping = described_class.new([0, 5, 10])

      expect(mapping.new_id(0)).to eq(0)
    end
  end

  describe "#old_id" do
    it "returns old GID for new GID" do
      mapping = described_class.new([0, 5, 10])

      expect(mapping.old_id(1)).to eq(5)
      expect(mapping.old_id(2)).to eq(10)
    end

    it "returns nil for invalid new GID" do
      mapping = described_class.new([0, 5, 10])

      expect(mapping.old_id(99)).to be_nil
    end

    it "handles GID 0" do
      mapping = described_class.new([0, 5, 10])

      expect(mapping.old_id(0)).to eq(0)
    end

    context "in retain GID mode" do
      it "returns old ID for mapped glyphs" do
        mapping = described_class.new([0, 5, 10], retain_gids: true)

        expect(mapping.old_id(5)).to eq(5)
        expect(mapping.old_id(10)).to eq(10)
      end

      it "returns nil for empty slots" do
        mapping = described_class.new([0, 5, 10], retain_gids: true)

        expect(mapping.old_id(3)).to be_nil
        expect(mapping.old_id(7)).to be_nil
      end
    end
  end

  describe "#size" do
    context "compact mode" do
      it "returns number of included glyphs" do
        mapping = described_class.new([0, 5, 10])

        expect(mapping.size).to eq(3)
      end

      it "handles single glyph" do
        mapping = described_class.new([0])

        expect(mapping.size).to eq(1)
      end

      it "handles many glyphs" do
        mapping = described_class.new((0..100).to_a)

        expect(mapping.size).to eq(101)
      end
    end

    context "retain GID mode" do
      it "returns highest GID + 1" do
        mapping = described_class.new([0, 5, 10], retain_gids: true)

        expect(mapping.size).to eq(11)
      end

      it "includes empty slots" do
        mapping = described_class.new([0, 100], retain_gids: true)

        expect(mapping.size).to eq(101)
      end
    end
  end

  describe "#include?" do
    it "returns true for included glyphs" do
      mapping = described_class.new([0, 5, 10])

      expect(mapping.include?(0)).to be(true)
      expect(mapping.include?(5)).to be(true)
      expect(mapping.include?(10)).to be(true)
    end

    it "returns false for excluded glyphs" do
      mapping = described_class.new([0, 5, 10])

      expect(mapping.include?(3)).to be(false)
      expect(mapping.include?(99)).to be(false)
    end

    it "works in retain GID mode" do
      mapping = described_class.new([0, 5, 10], retain_gids: true)

      expect(mapping.include?(5)).to be(true)
      expect(mapping.include?(3)).to be(false)
    end
  end

  describe "#old_ids" do
    it "returns sorted array of old IDs" do
      mapping = described_class.new([10, 0, 5])

      expect(mapping.old_ids).to eq([0, 5, 10])
    end

    it "returns array without duplicates" do
      mapping = described_class.new([0, 5, 5, 10])

      expect(mapping.old_ids).to eq([0, 5, 10])
    end

    it "works in retain GID mode" do
      mapping = described_class.new([10, 0, 5], retain_gids: true)

      expect(mapping.old_ids).to eq([0, 5, 10])
    end
  end

  describe "#new_ids" do
    context "compact mode" do
      it "returns sequential new IDs" do
        mapping = described_class.new([0, 5, 10])

        expect(mapping.new_ids).to eq([0, 1, 2])
      end
    end

    context "retain GID mode" do
      it "returns all GIDs including empty slots" do
        mapping = described_class.new([0, 5, 10], retain_gids: true)

        expect(mapping.new_ids).to eq((0..10).to_a)
      end
    end
  end

  describe "#each" do
    it "iterates over all mappings" do
      mapping = described_class.new([0, 5, 10])
      results = []

      mapping.each do |old_id, new_id|
        results << [old_id, new_id]
      end

      expect(results).to eq([[0, 0], [5, 1], [10, 2]])
    end

    it "returns enumerator without block" do
      mapping = described_class.new([0, 5, 10])

      expect(mapping.each).to be_a(Enumerator)
    end

    it "can be chained with enumerable methods" do
      mapping = described_class.new([0, 5, 10])

      result = mapping.each.map { |old_id, new_id| old_id * new_id }
      expect(result).to eq([0, 5, 20])
    end

    it "iterates in order of old IDs" do
      mapping = described_class.new([0, 5, 10])
      old_ids = []

      mapping.each { |old_id, _new_id| old_ids << old_id }

      expect(old_ids).to eq([0, 5, 10])
    end
  end

  describe "#retain_gids" do
    it "returns false in compact mode" do
      mapping = described_class.new([0, 5, 10])

      expect(mapping.retain_gids).to be(false)
    end

    it "returns true in retain GID mode" do
      mapping = described_class.new([0, 5, 10], retain_gids: true)

      expect(mapping.retain_gids).to be(true)
    end
  end

  describe "bidirectional mapping" do
    it "maintains consistency between old_to_new and new_to_old" do
      mapping = described_class.new([0, 5, 10, 15])

      mapping.old_ids.each do |old_id|
        new_id = mapping.new_id(old_id)
        expect(mapping.old_id(new_id)).to eq(old_id)
      end
    end

    it "works in retain GID mode" do
      mapping = described_class.new([0, 5, 10], retain_gids: true)

      [0, 5, 10].each do |gid|
        expect(mapping.new_id(gid)).to eq(gid)
        expect(mapping.old_id(gid)).to eq(gid)
      end
    end
  end

  describe "edge cases" do
    it "handles empty glyph list" do
      mapping = described_class.new([])

      expect(mapping.size).to eq(0)
      expect(mapping.old_ids).to eq([])
      expect(mapping.new_ids).to eq([])
    end

    it "handles single glyph (notdef only)" do
      mapping = described_class.new([0])

      expect(mapping.size).to eq(1)
      expect(mapping.new_id(0)).to eq(0)
      expect(mapping.old_id(0)).to eq(0)
    end

    it "handles large glyph counts" do
      gids = (0..1000).step(10).to_a
      mapping = described_class.new(gids)

      expect(mapping.size).to eq(101)
      expect(mapping.new_id(500)).to eq(50)
    end
  end

  describe "use cases" do
    context "web font subsetting" do
      it "creates compact mapping for reduced file size" do
        # Subset for "Hello World" might include these glyphs
        selected_gids = [0, 72, 101, 108, 111, 32, 87, 114, 100]
        mapping = described_class.new(selected_gids)

        # File contains only 9 glyphs instead of original count
        expect(mapping.size).to eq(9)

        # Glyph 72 (H) maps to position 2 after sorting [0, 32, 72, ...]
        expect(mapping.new_id(72)).to eq(2)
      end
    end

    context "PDF font subsetting with GID retention" do
      it "preserves original GIDs for PDF references" do
        selected_gids = [0, 10, 20, 30]
        mapping = described_class.new(selected_gids, retain_gids: true)

        # PDF can reference glyphs by original GIDs
        expect(mapping.new_id(10)).to eq(10)
        expect(mapping.new_id(20)).to eq(20)

        # But file is still larger due to empty slots
        expect(mapping.size).to eq(31) # 0..30
      end
    end

    context "incremental subsetting" do
      it "handles adding more glyphs" do
        initial = [0, 5, 10]
        extended = [0, 5, 10, 15, 20]

        described_class.new(initial)
        mapping2 = described_class.new(extended)

        # Original mappings stay the same
        expect(mapping2.new_id(0)).to eq(0)
        expect(mapping2.new_id(5)).to eq(1)
        expect(mapping2.new_id(10)).to eq(2)

        # New glyphs get next IDs
        expect(mapping2.new_id(15)).to eq(3)
        expect(mapping2.new_id(20)).to eq(4)
      end
    end

    context "CFF font subsetting" do
      it "handles CFF glyph ordering" do
        # CFF fonts have .notdef at 0
        cff_gids = [0, 100, 200, 300]
        mapping = described_class.new(cff_gids)

        expect(mapping.new_id(0)).to eq(0)
        expect(mapping.size).to eq(4)
      end
    end
  end

  describe "attribute readers" do
    it "exposes old_to_new mapping" do
      mapping = described_class.new([0, 5, 10])

      expect(mapping.old_to_new).to be_a(Hash)
      expect(mapping.old_to_new[5]).to eq(1)
    end

    it "exposes new_to_old mapping" do
      mapping = described_class.new([0, 5, 10])

      expect(mapping.new_to_old).to be_a(Hash)
      expect(mapping.new_to_old[1]).to eq(5)
    end

    it "exposes retain_gids setting" do
      mapping = described_class.new([0, 5, 10], retain_gids: true)

      expect(mapping.retain_gids).to be(true)
    end
  end
end
