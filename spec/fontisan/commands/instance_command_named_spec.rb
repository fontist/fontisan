# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "stringio"

RSpec.describe "fontisan instance --named-instance through the CLI" do
  let(:vf) do
    File.expand_path("../../fixtures/fonts/MonaSansVF/MonaSansMonoVF[wght].ttf", __dir__)
  end
  let(:dir) { Dir.mktmpdir }
  let(:out) { File.join(dir, "out.ttf") }

  after { FileUtils.remove_entry(dir) }

  def cli(*args)
    saved = [$stdout, $stderr]
    $stdout = $stderr = StringIO.new
    begin
      Fontisan::Cli.start(args)
    rescue SystemExit => e
      raise "CLI exited #{e.status}: #{$stderr.string}"
    end
    $stdout.string
  ensure
    $stdout, $stderr = saved
  end

  def cli_error(*args)
    saved = [$stdout, $stderr]
    $stderr = StringIO.new
    $stdout = StringIO.new
    begin
      Fontisan::Cli.start(args)
      nil
    rescue SystemExit => e
      [e.status, $stderr.string]
    end
  ensure
    $stdout, $stderr = saved
  end

  it "writes the named instance, equal to the generator given Integer 0" do
    cli("instance", vf, "--named-instance", "0", "--output", out)

    font = Fontisan::FontLoader.load(vf)
    expected = File.join(dir, "expected.ttf")
    tables = Fontisan::Variation::InstanceGenerator.new(font).generate_named_instance(0)
    Fontisan::Variation::InstanceWriter.write(tables, expected,
                                              format: nil, source_format: :ttf,
                                              optimize: false)
    expect(File.binread(out)).to eq(File.binread(expected))
  end

  it "rejects a non-integer value with a clear error" do
    status, err = cli_error("instance", vf, "--named-instance", "Bold", "--output", out)
    expect(status).to eq(1)
    expect(err).to include("--named-instance must be an integer index")
    expect(File.exist?(out)).to be(false)
  end

  it "rejects an out-of-range value with a clear error" do
    status, err = cli_error("instance", vf, "--named-instance", "999", "--output", out)
    expect(status).to eq(1)
    expect(err).to match(/out of range \(font has \d+ named instances\)/)
  end
end
