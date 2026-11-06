# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# A layout table whose every script re-walks the same long feature list used
# to be re-parsed once per script (scripts x table length), so the audit of a
# 137 KB GSUB took minutes. It must use the once-parsed, work-budgeted path
# the native tiers use. The font is built here; nothing binary is committed.
RSpec.describe "audit of a layout-heavy GSUB" do
  # Distinct 4-letter tag for index i.
  def tag(index)
    [65 + (index / 17_576 % 26), 97 + (index / 676 % 26),
     97 + (index / 26 % 26), 97 + (index % 26)].pack("C*")
  end

  # An sfnt holding only a GSUB with +scripts+ records that share one Script
  # table whose DefaultLangSys lists +features+ feature indices.
  def gsub_font(scripts, features)
    script_table = 2 + (6 * scripts)
    records = Array.new(scripts) { |i| tag(i) + [script_table].pack("n") }
    indices = Array.new(features) { |i| [i].pack("n") }
    lang_sys = [4, 0, 0, 0xFFFF, features].pack("nnnnn")
    script_list = [scripts].pack("n") + records.join + lang_sys + indices.join
    feature_records = Array.new(features) do |i|
      tag(i) + [2 + (6 * features)].pack("n")
    end
    feature_list = [features].pack("n") + feature_records.join + ("\0" * 4)
    # header: version 1.0, scriptList, featureList, lookupList offsets
    gsub = [1, 0, 10 + feature_list.bytesize, 10, 0].pack("nnnnn")
    gsub += feature_list + script_list
    sfnt = [0x00010000, 1, 16, 0, 0].pack("Nnnnn")
    "#{sfnt}GSUB#{[0, 28, gsub.bytesize].pack('NNN')}#{gsub}"
  end

  def audit_seconds(bytes, validate:)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "x.otf")
      File.binwrite(path, bytes)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = Fontisan::Reference.audit(path, validate: validate)
      [result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
    end
  end

  [false, true].each do |validate|
    it "finishes a generated 137 KB GSUB fast (validate: #{validate})" do
      bytes = gsub_font(10_900, 9_000)
      expect(bytes.bytesize).to be > 130_000

      result, took = audit_seconds(bytes, validate: validate)

      expect(took).to be < 10
      expect(result.first["opentype_scripts"].size).to eq(10_900)
    end
  end
end
