# frozen_string_literal: true

require "spec_helper"
require_relative "../../benchmark/corpus/tiers"

RSpec.describe FontisanBench::Tiers do
  let(:baseline) do
    { "tolerance" => 0.25, "factors" => { "audit_file" => 40.0, "audit_dir" => 30.0, "scan_dir" => 10.0 } }
  end

  let(:ruby) { ops(audit_file: 0.4, audit_dir: 0.6, scan_dir: 0.2) }
  let(:healthy) { ops(audit_file: 0.4 / 40, audit_dir: 0.6 / 30, scan_dir: 0.2 / 10) }

  # One round per tier; times in seconds, rss in KB.
  def measurement(ruby:, native:, rss: [58_000, 57_000], ffi: native, ffi_rss: rss[1])
    m = FontisanBench::Measurement.new
    { "ruby" => [ruby, rss[0]], "native" => [native, rss[1]], "ffi" => [ffi, ffi_rss] }.each do |tier, (ops, kb)|
      m.record(tier, { "ops" => ops, "scan_peak_rss_kb" => kb })
    end
    m
  end

  def ops(audit_file:, audit_dir:, scan_dir:)
    { "audit_file" => audit_file, "audit_dir" => audit_dir, "scan_dir" => scan_dir }
  end

  def verdicts(rows)
    rows.to_h { |r| [r.metric, r.status] }
  end

  it "passes a native tier at its expected factors" do
    rows = described_class.rows(measurement(ruby: ruby, native: healthy), baseline: baseline)
    expect(described_class.failed?(rows)).to be(false)
  end

  it "passes a native tier within the tolerance below the expected factor" do
    slower = ops(audit_file: 0.4 / 31, audit_dir: 0.6 / 23, scan_dir: 0.2 / 7.6)
    rows = described_class.rows(measurement(ruby: ruby, native: slower), baseline: baseline)
    expect(described_class.failed?(rows)).to be(false)
  end

  it "fails a native slowdown that stays well above the 1.00x floor (audit_dir 4x slower)" do
    slow = healthy.merge("audit_dir" => 0.6 / 30 * 4)
    rows = described_class.rows(measurement(ruby: ruby, native: slow), baseline: baseline)
    expect(verdicts(rows)).to include("audit_dir" => "FAIL", "scan_dir" => "ok")
    expect(rows.find { |r| r.metric == "audit_dir" }.note).to match(/more than 25% below the expected 30.00x/)
  end

  it "gates audit_file too" do
    slow = healthy.merge("audit_file" => 0.4 / 40 * 26)
    rows = described_class.rows(measurement(ruby: ruby, native: slow), baseline: baseline)
    expect(verdicts(rows)).to include("audit_file" => "FAIL")
  end

  it "still fails below the 1.00x floor" do
    slow = healthy.merge("scan_dir" => 0.3)
    rows = described_class.rows(measurement(ruby: ruby, native: slow), baseline: baseline)
    expect(rows.find { |r| r.metric == "scan_dir" }.note).to eq("native is slower than ruby")
  end

  it "holds a platform without a baseline to the floor and says so" do
    rows = described_class.rows(measurement(ruby: ruby, native: ops(audit_file: 0.3, audit_dir: 0.5, scan_dir: 0.19)))
    expect(described_class.failed?(rows)).to be(false)
    expect(rows.find { |r| r.metric == "audit_dir" }.note).to include("no baseline")
  end

  describe "ffi tier" do
    it "fails an ffi tier 30x slower than ruby while native is healthy" do
      ffi = ops(audit_file: 0.4 * 30, audit_dir: 0.6 * 30, scan_dir: 0.2 * 30)
      rows = described_class.rows(measurement(ruby: ruby, native: healthy, ffi: ffi), baseline: baseline)
      expect(verdicts(rows)).to include("audit_file" => "FAIL", "audit_dir" => "FAIL", "scan_dir" => "FAIL")
      expect(rows.find { |r| r.metric == "scan_dir" }.note).to eq("ffi is slower than ruby")
    end

    it "fails ffi slower than ruby on a single gated op" do
      ffi = healthy.merge("scan_dir" => 0.3)
      rows = described_class.rows(measurement(ruby: ruby, native: healthy, ffi: ffi), baseline: baseline)
      expect(verdicts(rows)).to include("audit_file" => "ok", "scan_dir" => "FAIL")
    end

    it "does not hold ffi to the native baseline, only to the floor" do
      ffi = ops(audit_file: 0.4 / 2, audit_dir: 0.6 / 2, scan_dir: 0.2 / 2)
      rows = described_class.rows(measurement(ruby: ruby, native: healthy, ffi: ffi), baseline: baseline)
      expect(described_class.failed?(rows)).to be(false)
    end

    it "fails ffi peak RSS at 3x ruby's while native RSS is fine" do
      rows = described_class.rows(measurement(ruby: ruby, native: healthy, ffi_rss: 174_000), baseline: baseline)
      expect(verdicts(rows)["scan_peak_rss_kb"]).to eq("FAIL")
      expect(rows.last.note).to start_with("ffi peak RSS")
    end

    it "passes when the ffi tier did not run (no cdylib)" do
      m = FontisanBench::Measurement.new
      m.record("ruby", { "ops" => ruby, "scan_peak_rss_kb" => 58_000 })
      m.record("native", { "ops" => healthy, "scan_peak_rss_kb" => 57_000 })
      expect(described_class.failed?(described_class.rows(m, baseline: baseline))).to be(false)
    end
  end

  describe "native cases (unchanged)" do
    it "still fails native at 19x against an expected 33.17x" do
      base = { "tolerance" => 0.25, "factors" => { "audit_dir" => 33.17 } }
      slow = healthy.merge("audit_dir" => 0.6 / 19)
      rows = described_class.rows(measurement(ruby: ruby, native: slow, ffi: healthy), baseline: base)
      expect(verdicts(rows)["audit_dir"]).to eq("FAIL")
    end
  end

  describe "peak RSS" do
    it "tolerates noise above ruby's, as long as it stays within 3%" do
      rows = described_class.rows(measurement(ruby: ruby, native: healthy, rss: [58_000, 59_000]), baseline: baseline)
      expect(verdicts(rows)["scan_peak_rss_kb"]).to eq("ok")
    end

    it "fails a real blow-up" do
      rows = described_class.rows(measurement(ruby: ruby, native: healthy, rss: [58_000, 78_000]), baseline: baseline)
      expect(verdicts(rows)["scan_peak_rss_kb"]).to eq("FAIL")
    end
  end

  describe ".baseline" do
    it "commits factors for every CI platform and none for an unmeasured one" do
      %w[x86_64-linux x86_64-linux-musl aarch64-linux x86_64-darwin x64-mingw-ucrt].each do |platform|
        factors = described_class.baseline(platform).fetch("factors")
        expect(factors.keys).to match_array(%w[audit_file audit_dir scan_dir]), platform
      end
      expect(described_class.baseline("riscv-linux")).to be_nil
    end
  end
end
