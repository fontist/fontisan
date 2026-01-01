# frozen_string_literal: true

require "spec_helper"
require "fontisan/converters/woff2_encoder"
require "tempfile"

RSpec.describe Fontisan::Converters::Woff2Encoder, "integration" do
  let(:encoder) { described_class.new }
  
  describe "full TTF to WOFF2 conversion" do
    let(:font_path) { fixture_path("fonttools/TestTTF.ttf") }
    let(:font) { Fontisan::FontLoader.load(font_path) }
    
    it "successfully converts TTF to WOFF2 with transformations" do
      result = encoder.convert(font, transform_tables: true)
      
      expect(result).to have_key(:woff2_binary)
      expect(result[:woff2_binary]).to be_a(String)
      expect(result[:woff2_binary].bytesize).to be > 0
      
      # Check WOFF2 signature
      signature = result[:woff2_binary][0, 4]
      expect(signature).to eq("wOF2")
    end
    
    it "produces valid WOFF2 structure" do
      result = encoder.convert(font, transform_tables: true)
      woff2_binary = result[:woff2_binary]
      
      # Parse header
      io = StringIO.new(woff2_binary)
      signature = io.read(4)
      flavor = io.read(4).unpack1("N")
      length = io.read(4).unpack1("N")
      num_tables = io.read(2).unpack1("n")
      
      expect(signature).to eq("wOF2")
      expect(flavor).to eq(0x00010000) # TrueType
      expect(length).to eq(woff2_binary.bytesize)
      expect(num_tables).to be > 0
    end
    
    it "achieves compression with transformations" do
      original_size = font.table_data.values.sum(&:bytesize)
      
      result = encoder.convert(font, transform_tables: true)
      woff2_size = result[:woff2_binary].bytesize
      
      # WOFF2 should be smaller than raw table data
      expect(woff2_size).to be < original_size
      
      # Typical compression ratio should be significant
      compression_ratio = (original_size - woff2_size) / original_size.to_f
      expect(compression_ratio).to be > 0.2 # At least 20% compression
    end
    
    it "handles fonts without transformations" do
      result = encoder.convert(font, transform_tables: false)
      
      expect(result[:woff2_binary]).to be_a(String)
      expect(result[:woff2_binary].bytesize).to be > 0
      
      # Check signature
      signature = result[:woff2_binary][0, 4]
      expect(signature).to eq("wOF2")
    end
    
    it "writes valid output file via pipeline" do
      Tempfile.create(["test", ".woff2"]) do |tempfile|
        # Use the full pipeline
        pipeline = Fontisan::Pipeline::TransformationPipeline.new(
          font_path,
          tempfile.path,
          target_format: :woff2,
          validate: false # Skip validation since we're testing encoding
        )
        
        result = pipeline.transform
        
        expect(result[:success]).to be true
        expect(File.exist?(tempfile.path)).to be true
        expect(File.size(tempfile.path)).to be > 0
        
        # Check WOFF2 signature
        signature = File.binread(tempfile.path, 4)
        expect(signature).to eq("wOF2")
      end
    end
  end
end
