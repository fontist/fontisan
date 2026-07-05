# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Woff2::TripletCodec do
  describe "#encode / #decode round-trip" do
    cases = [
      { dx: 0, dy: 0, on_curve: true },     # both zero (y-only branch picks)
      { dx: 0, dy: 100, on_curve: true },   # y-only, small
      { dx: 200, dy: 0, on_curve: false },  # x-only
      { dx: 50, dy: 50, on_curve: true },   # nibble pair
      { dx: 500, dy: 500, on_curve: true }, # byte pair
      { dx: 2000, dy: 2000, on_curve: true }, # 12-bit pair
      { dx: 50_000, dy: 50_000, on_curve: true }, # 16-bit pair
      { dx: -100, dy: 200, on_curve: false },
      { dx: -5000, dy: 8000, on_curve: true },
      { dx: 1, dy: 64, on_curve: true },    # boundary: nibble range edge
      { dx: 65, dy: 65, on_curve: true },   # boundary: just past nibble
      { dx: 768, dy: 768, on_curve: true }, # boundary: just past byte pair
    ]

    cases.each do |c|
      it "round-trips #{c}" do
        flag, payload = described_class.encode(c[:dx], c[:dy], on_curve: c[:on_curve])
        rdx, rdy, roc = described_class.decode(flag, payload)
        expect([rdx, rdy, roc]).to eq([c[:dx], c[:dy], c[:on_curve]])
      end
    end
  end

  describe "#encode payload size" do
    it "uses 1 byte for x=0,y<1280 (y-only)" do
      _, payload = described_class.encode(0, 100, on_curve: true)
      expect(payload.length).to eq(1)
    end

    it "uses 1 byte for y=0,x<1280 (x-only)" do
      _, payload = described_class.encode(100, 0, on_curve: true)
      expect(payload.length).to eq(1)
    end

    it "uses 1 byte for both coords <65 (nibble pair)" do
      _, payload = described_class.encode(50, 50, on_curve: true)
      expect(payload.length).to eq(1)
    end

    it "uses 2 bytes for coords <769 (byte pair)" do
      _, payload = described_class.encode(500, 500, on_curve: true)
      expect(payload.length).to eq(2)
    end

    it "uses 3 bytes for coords <4096 (12-bit pair)" do
      _, payload = described_class.encode(2000, 2000, on_curve: true)
      expect(payload.length).to eq(3)
    end

    it "uses 4 bytes for very large coords (16-bit pair)" do
      _, payload = described_class.encode(50_000, 50_000, on_curve: true)
      expect(payload.length).to eq(4)
    end
  end

  describe "on-curve flag bit" do
    it "sets bit 7 for off-curve points" do
      flag, = described_class.encode(0, 100, on_curve: false)
      expect(flag & 0x80).to be_nonzero
    end

    it "clears bit 7 for on-curve points" do
      flag, = described_class.encode(0, 100, on_curve: true)
      expect(flag & 0x80).to be_zero
    end
  end
end
