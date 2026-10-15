# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Commands::ExportCommand do
  let(:font_path) do
    font_fixture_path("NotoSans", "NotoSans-Regular.ttf")
  end
  let(:output_path) { File.join(Dir.mktmpdir, "font.yaml") }

  after do
    FileUtils.rm_rf(File.dirname(output_path))
  end

  it "exports a font when initialized with the documented input keyword" do
    command = described_class.new(input: font_path, output: output_path)

    expect { command.run }
      .to output(/Exported to #{Regexp.escape(output_path)}/).to_stdout
    expect(File.read(output_path)).to include("metadata:")
  end

  it "returns failure when the input path is empty" do
    command = nil
    expect { command = described_class.new(input: "") }
      .to output(/Error loading font/).to_stdout

    expect(command.run).to eq(1)
  end
end
