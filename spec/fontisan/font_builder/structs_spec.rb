# frozen_string_literal: true

require "spec_helper"
require "fontisan/font_builder"

RSpec.describe Fontisan::FontBuilder::Outline do
  describe "#initialize" do
    it "defaults to empty contours and no instructions" do
      o = described_class.new
      expect(o.contours).to eq([])
      expect(o.instructions).to be_nil
      expect(o.components).to eq([])
    end
  end

  describe "#composite?" do
    it "is false for simple outlines" do
      expect(described_class.new.composite?).to be(false)
    end

    it "is true when components is non-empty" do
      o = described_class.new(components: [{ gid: 5 }])
      expect(o.composite?).to be(true)
    end
  end

  describe "#point_count" do
    it "is 0 for an empty outline" do
      expect(described_class.new.point_count).to eq(0)
    end

    it "sums points across all contours" do
      p1 = Fontisan::FontBuilder::Point.new(x: 0, y: 0)
      p2 = Fontisan::FontBuilder::Point.new(x: 100, y: 0)
      p3 = Fontisan::FontBuilder::Point.new(x: 50, y: 100)
      o = described_class.new(contours: [[p1, p2], [p3]])
      expect(o.point_count).to eq(3)
    end
  end
end

RSpec.describe Fontisan::FontBuilder::Point do
  describe "#initialize" do
    it "defaults to origin, on-curve" do
      p = described_class.new
      expect(p.x).to eq(0)
      expect(p.y).to eq(0)
      expect(p.on_curve).to be(true)
    end
  end

  describe "#delta" do
    it "computes coordinate deltas against the previous point" do
      prev = described_class.new(x: 100, y: 100)
      cur = described_class.new(x: 250, y: 80)
      d = cur.delta(prev)
      expect(d.x).to eq(150)
      expect(d.y).to eq(-20)
    end

    it "treats nil previous as origin" do
      cur = described_class.new(x: 50, y: 60)
      d = cur.delta(nil)
      expect(d.x).to eq(50)
      expect(d.y).to eq(60)
    end

    it "preserves on_curve flag" do
      cur = described_class.new(x: 0, y: 0, on_curve: false)
      expect(cur.delta(nil).on_curve).to be(false)
    end
  end
end

RSpec.describe Fontisan::FontBuilder::NameRecord do
  describe "#initialize" do
    it "defaults platform/encoding/language to Windows Unicode BMP English" do
      r = described_class.new(name_id: 1, string: "Test")
      expect(r.platform_id).to eq(3)
      expect(r.encoding_id).to eq(1)
      expect(r.language_id).to eq(0x0409)
    end

    it "accepts explicit overrides" do
      r = described_class.new(name_id: 1, string: "Test",
                              platform_id: 1, encoding_id: 0, language_id: 0)
      expect(r.platform_id).to eq(1)
    end
  end
end

RSpec.describe Fontisan::FontBuilder::Metrics do
  describe "#initialize" do
    it "defaults to zero advance and zero lsb" do
      m = described_class.new
      expect(m.advance_width).to eq(0)
      expect(m.left_side_bearing).to eq(0)
    end
  end
end

RSpec.describe Fontisan::FontBuilder::GlyphEntry do
  describe "#initialize" do
    it "defaults to an empty Outline + zero Metrics" do
      e = described_class.new
      expect(e.outline).to be_a(Fontisan::FontBuilder::Outline)
      expect(e.metrics).to be_a(Fontisan::FontBuilder::Metrics)
    end
  end
end
