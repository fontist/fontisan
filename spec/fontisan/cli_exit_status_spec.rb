# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"

RSpec.describe Fontisan::Cli, ".exit_on_failure?" do
  let(:exe) { File.expand_path("../../exe/fontisan", __dir__) }

  def run_cli(*)
    Open3.capture3(RbConfig.ruby, "-I#{File.expand_path('../../lib', __dir__)}", exe, *)
  end

  it "is true so a Thor::Error ends the process non-zero" do
    expect(described_class.exit_on_failure?).to be(true)
  end

  it "exits non-zero for a missing --output" do
    _out, err, status = run_cli("convert", "x.ttf", "--to", "woff")
    expect(err).to include("Output path is required")
    expect(status.exitstatus).to eq(1)
  end

  it "exits non-zero for an unknown command" do
    _out, err, status = run_cli("nosuchcommand")
    expect(err).to include("Could not find command")
    expect(status.exitstatus).to eq(1)
  end
end
