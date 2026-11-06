# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"

# A fresh process (the CLI, or a script calling Fontisan.convert) reaches the
# engine before anything has loaded Fontisan::Reference, which installs the
# tiers. A forced native tier must still be found there.
RSpec.describe "Fontisan::Engine in a fresh process" do
  let(:lib) { File.expand_path("../../lib", __dir__) }
  let(:script) { 'require "fontisan"; Fontisan::Engine.setup!; print "found"' }

  it "finds a forced native tier without Reference loaded first" do
    skip "native tier not built" unless Fontisan::Native.available?

    out, err, status = Open3.capture3(
      { "FONTISAN_ENGINE" => "native", "FONTISAN_ENGINE_STRICT" => "1" },
      RbConfig.ruby, "-I#{lib}", "-e", script
    )
    expect([status.success?, out]).to eq([true, "found"]), err
  end
end
