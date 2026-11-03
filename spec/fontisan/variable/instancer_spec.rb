# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Variable::Instancer do
  let(:fixture_dir) { File.expand_path("../../fixtures/fonts/MonaSansVF", __dir__) }
  let(:font) { Fontisan::FontLoader.load(File.join(fixture_dir, "MonaSansMonoVF[wght].ttf")) }
  let(:instancer) { described_class.new(font) }

  def load_binary(binary)
    path = File.join(Dir.mktmpdir, "i.ttf")
    File.binwrite(path, binary)
    Fontisan::FontLoader.load(path)
  end

  it "reports the font's axes" do
    expect(instancer.axis_tags).to eq(["wght"])
    expect(instancer.axes.first.minimum).to eq(200)
    expect(instancer.axes.first.maximum).to eq(900)
  end

  it "lists the named instances with their names and coordinates" do
    named = instancer.named_instances
    expect(named.map { |n| n[:name] }).to include("Light", "Bold")
    expect(named.find { |n| n[:name] == "Light" }[:coordinates]).to eq("wght" => 300.0)
  end

  it "builds a static font at the requested coordinates" do
    static = load_binary(instancer.instance("wght" => 700))
    expect(static.has_table?("fvar")).to be(false)
    expect(static.table("OS/2").us_weight_class).to eq(700)
  end

  it "builds different outlines for different weights" do
    expect(load_binary(instancer.instance("wght" => 300)).table_data["glyf"])
      .not_to eq(load_binary(instancer.instance("wght" => 700)).table_data["glyf"])
  end

  it "builds a named instance equal to the same coordinates" do
    expect(instancer.instance_named("Light")).to eq(instancer.instance("wght" => 300))
  end

  it "raises for an unknown named instance" do
    expect { instancer.instance_named("Nope") }.to raise_error(ArgumentError, /Nope/)
  end

  it "raises for a static font" do
    static = Fontisan::FontLoader.load(
      File.expand_path("../../fixtures/fonttools/TestTTF.ttf", __dir__),
    )
    expect { described_class.new(static) }.to raise_error(ArgumentError, /not a variable font/)
  end

  it "raises for an out-of-range value" do
    expect { instancer.instance("wght" => 5000) }
      .to raise_error(Fontisan::InvalidCoordinatesError)
  end
end
