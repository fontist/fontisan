# frozen_string_literal: true

require "spec_helper"

# The Windows engine tiers report "D:/a/dir\file.ttf" for a row under
# "D:/a/dir"; the parity fallback job's `mixed` scenario read those rows as
# absolute paths (and so credited the forced tier with dfont and Type 1 files).
RSpec.describe Fontisan::Reference, ".relative_row_path" do
  it "strips the directory from a row that joins it with a Windows separator" do
    rel = described_class.relative_row_path("D:/a/dir", "D:/a/dir\\TestTTF.ttf", alt_separator: "\\")
    expect(rel).to eq("TestTTF.ttf")
  end

  it "normalises a backslash directory and nested rows" do
    rel = described_class.relative_row_path("D:\\a\\dir\\", "D:\\a\\dir\\sub\\f.otf", alt_separator: "\\")
    expect(rel).to eq("sub/f.otf")
  end

  it "keeps a backslash in a POSIX file name" do
    expect(described_class.relative_row_path("/d", "/d/a\\b.ttf", alt_separator: nil)).to eq("a\\b.ttf")
  end

  it "strips a plain POSIX prefix" do
    expect(described_class.relative_row_path("/d/", "/d/x/y.ttf")).to eq("x/y.ttf")
  end
end
