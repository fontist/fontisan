# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Export::Exporter do
  let(:font_path) { font_fixture_path("NotoSans", "NotoSans-Regular.ttf") }
  let(:font) { Fontisan::FontLoader.load(font_path) }
  let(:binary_format) { :hex }
  let(:exporter) do
    described_class.new(font, font_path, binary_format: binary_format)
  end
  let(:table) { font.table("head") }

  %i[hex base64].each do |format|
    context "with #{format} binary encoding" do
      let(:binary_format) { format }

      it "uses the configured encoding for serialization fallback" do
        allow(table).to receive(:snapshot)
          .and_raise(StandardError, "forced serialization failure")

        export = exporter.export(tables: ["head"])
        fallback = export.find_table("head")
        expected_data = if format == :hex
                          table.to_binary_s.unpack1("H*")
                        else
                          Base64.strict_encode64(table.to_binary_s)
                        end

        expect(fallback.parsed).to be(false)
        expect(fallback.data).to eq(expected_data)
        expect(JSON.parse(fallback.fields)).to eq(
          "error" => "forced serialization failure",
        )
      end
    end
  end
end
