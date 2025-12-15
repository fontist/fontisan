# frozen_string_literal: true

require "spec_helper"
require "fontisan"

RSpec.describe "Round-Trip Validation (Simplified)" do
  let(:ttf_font_path) do
    File.join(File.dirname(__FILE__), "..", "fixtures", "fonts",
              "NotoSans-Regular.ttf")
  end

  let(:converter) { Fontisan::Converters::OutlineConverter.new }

  describe "TTF → OTF conversion" do
    it "successfully converts without optimization" do
      font = Fontisan::FontLoader.load(ttf_font_path)

      # Convert to OTF without optimization
      tables = converter.convert(font,
                                 target_format: :otf,
                                 optimize_subroutines: false)

      # Verify CFF table was created
      expect(tables["CFF "]).not_to be_nil
      expect(tables["CFF "].bytesize).to be > 0

      # Verify glyf/loca were removed
      expect(tables["glyf"]).to be_nil
      expect(tables["loca"]).to be_nil

      # Verify helper tables were updated
      expect(tables["maxp"]).not_to be_nil
      expect(tables["head"]).not_to be_nil
    end
  end
end
