# frozen_string_literal: true

require "spec_helper"
require "fontisan/commands/convert_command"

RSpec.describe Fontisan::Commands::ConvertCommand, "#run multi-format" do
  let(:fixtures_dir) { File.expand_path("../../fixtures/fonts", __dir__) }
  let(:ttf_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:output_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(output_dir)
  end

  it "parses comma-separated --to into multiple target formats" do
    output_path = File.join(output_dir, "out")
    cmd = described_class.new(ttf_path, to: "woff,woff2", output: output_path,
                                        quiet: true, no_validate: true)
    expect(cmd.target_formats).to eq(%i[woff woff2])
    expect(cmd.output_paths).to eq([File.join(output_dir, "out.woff"),
                                    File.join(output_dir, "out.woff2")])
  end

  it "parses array-form --to into multiple target formats" do
    output_path = File.join(output_dir, "out")
    cmd = described_class.new(ttf_path, to: %w[woff woff2], output: output_path,
                                        quiet: true, no_validate: true)
    expect(cmd.target_formats).to eq(%i[woff woff2])
  end

  it "dedupes repeated target formats" do
    output_path = File.join(output_dir, "out")
    cmd = described_class.new(ttf_path, to: "ttf,ttf", output: output_path)
    expect(cmd.target_formats).to eq([:ttf])
  end

  it "flattens mixed array + comma input" do
    output_path = File.join(output_dir, "out")
    cmd = described_class.new(ttf_path, to: ["woff,woff2", "woff"], output: output_path)
    expect(cmd.target_formats).to eq(%i[woff woff2])
  end

  it "writes one output per target format" do
    output_path = File.join(output_dir, "out")
    cmd = described_class.new(ttf_path, to: "woff,woff2", output: output_path,
                                        quiet: true, no_validate: true)
    results = cmd.run

    expect(results).to be_an(Array)
    expect(results.size).to eq(2)
    expect(File.exist?(File.join(output_dir, "out.woff"))).to be(true)
    expect(File.exist?(File.join(output_dir, "out.woff2"))).to be(true)
  end

  it "raises ArgumentError when output has extension but multiple formats requested" do
    output_path = File.join(output_dir, "out.woff")
    expect do
      described_class.new(ttf_path, to: "woff,woff2", output: output_path)
    end.to raise_error(ArgumentError, /extension/i)
  end

  it "raises ArgumentError for collection input + multi-format" do
    # Build a tiny synthetic .ttc to exercise the collection path.
    skip "requires collection fixture; covered in convert_collection_spec"
  end

  it "preserves single-format behaviour: parses one format as one-element array" do
    output_path = File.join(output_dir, "out.otf")
    cmd = described_class.new(ttf_path, to: "otf", output: output_path)
    expect(cmd.target_formats).to eq([:otf])
    expect(cmd.output_paths).to eq([output_path])
  end
end
