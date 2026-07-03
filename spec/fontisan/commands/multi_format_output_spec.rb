# frozen_string_literal: true

require "spec_helper"
require "fontisan/commands/multi_format_output"

RSpec.describe Fontisan::Commands::MultiFormatOutput do
  describe "#paths" do
    it "uses the given path as-is when one format and path has extension" do
      out = described_class.new("out.ttf", [:ttf])
      expect(out.paths).to eq(["out.ttf"])
    end

    it "appends .<format> when one format and path has no extension" do
      out = described_class.new("out", [:ttf])
      expect(out.paths).to eq(["out.ttf"])
    end

    it "appends .<format> per target when many formats and path has no extension" do
      out = described_class.new("out", %i[woff woff2])
      expect(out.paths).to eq(["out.woff", "out.woff2"])
    end

    it "raises ArgumentError when many formats and path has extension" do
      out = described_class.new("out.ttf", %i[woff woff2])
      expect { out.paths }.to raise_error(ArgumentError, /ambiguous|extension/i)
    end

    it "preserves target format order in the resolved paths" do
      out = described_class.new("base", %i[woff woff2 ttf])
      expect(out.paths).to eq(%w[base.woff base.woff2 base.ttf])
    end
  end
end
