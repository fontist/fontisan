# frozen_string_literal: true

require "spec_helper"
require "fontisan/ufo/info"

RSpec.describe Fontisan::Ufo::Info, ".for_subfont" do
  it "builds an Info with the subfont name embedded in family and PS name" do
    info = described_class.for_subfont(family: "essenfont", subfont: :SIP,
                                       version: "0.1")
    expect(info.family_name).to eq("essenfont SIP")
    expect(info.postscript_font_name).to eq("essenfont-SIP")
    expect(info.postscript_full_name).to eq("essenfont SIP")
  end

  it "parses major.minor version" do
    info = described_class.for_subfont(family: "F", subfont: :S, version: "2.5")
    expect(info.version_major).to eq(2)
    expect(info.version_minor).to eq(5)
  end

  it "drops the patch component of semver versions" do
    info = described_class.for_subfont(family: "F", subfont: :S, version: "1.2.3")
    expect([info.version_major, info.version_minor]).to eq([1, 2])
  end

  it "accepts a bare integer version" do
    info = described_class.for_subfont(family: "F", subfont: :S, version: "3")
    expect([info.version_major, info.version_minor]).to eq([3, 0])
  end

  it "defaults subfamily to Regular" do
    info = described_class.for_subfont(family: "F", subfont: :S, version: "0.1")
    expect(info.style_name).to eq("Regular")
  end

  it "stores trademark in extras under openTypeNameTrademark" do
    info = described_class.for_subfont(family: "F", subfont: :S, version: "0.1",
                                       trademark: "© Acme")
    expect(info.extras["openTypeNameTrademark"]).to eq("© Acme")
  end

  it "omits copyright when not supplied" do
    info = described_class.for_subfont(family: "F", subfont: :S, version: "0.1")
    expect(info.copyright).to be_nil
  end

  it "includes copyright when supplied" do
    info = described_class.for_subfont(family: "F", subfont: :S, version: "0.1",
                                       copyright: "© 2026")
    expect(info.copyright).to eq("© 2026")
  end
end
