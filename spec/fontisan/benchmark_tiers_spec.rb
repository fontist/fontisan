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
  def measurement(ruby:, native:, rss: [58_000, 57_000])
    m = FontisanBench::Measurement.new
    { "ruby" => [ruby, rss[0]], "native" => [native, rss[1]], "ffi" => [native, rss[1]] }.each do |tier, (ops, kb)|
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
