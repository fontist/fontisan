# # frozen_string_literal: true

# require "spec_helper"

# RSpec.describe "TTX round-trip conversion" do
#   describe "TestTTF font" do
#     let(:ttf_path) { "spec/fixtures/fonttools/TestTTF.ttf" }
#     let(:reference_ttx_path) { "spec/fixtures/fonttools/TestTTF.ttx" }

#     it "loads TTF font successfully" do
#       font = Fontisan::FontLoader.load(ttf_path)
#       expect(font).not_to be_nil
#       expect(font.header.sfnt_version.to_i).to eq(0x00010000)
#     end

#     it "generates TTX from TTF" do
#       font = Fontisan::FontLoader.load(ttf_path)
#       exporter = Fontisan::Export::Exporter.new(font, ttf_path)

#       ttx_xml = exporter.to_ttx

#       expect(ttx_xml).to be_a(String)
#       expect(ttx_xml).to include("<ttFont")
#       expect(ttx_xml).to include("<GlyphOrder>")
#       expect(ttx_xml).to include("<head>")
#       expect(ttx_xml).to include("<name>")
#     end

#     it "generates TTX with correct glyph count" do
#       font = Fontisan::FontLoader.load(ttf_path)
#       exporter = Fontisan::Export::Exporter.new(font, ttf_path)

#       ttx_xml = exporter.to_ttx
#       doc = Nokogiri::XML(ttx_xml)

#       glyph_ids = doc.xpath("//GlyphID")
#       expect(glyph_ids.count).to eq(6) # TestTTF has 6 glyphs

#       # Verify glyph names
#       names = glyph_ids.map { |g| g["name"] }
#       expect(names).to include(".notdef", ".null", "CR", "space", "period", "ellipsis")
#     end

#     it "generates TTX with valid head table" do
#       font = Fontisan::FontLoader.load(ttf_path)
#       exporter = Fontisan::Export::Exporter.new(font, ttf_path)

#       ttx_xml = exporter.to_ttx(tables: ["head"])
#       doc = Nokogiri::XML(ttx_xml)

#       head = doc.at_xpath("//head")
#       expect(head).not_to be_nil

#       # Check required head elements
#       expect(head.at_xpath("tableVersion")).not_to be_nil
#       expect(head.at_xpath("unitsPerEm")).not_to be_nil
#       expect(head.at_xpath("unitsPerEm")["value"]).to eq("1000")
#     end

#     it "generates parseable TTX" do
#       font = Fontisan::FontLoader.load(ttf_path)
#       exporter = Fontisan::Export::Exporter.new(font, ttf_path)

#       ttx_xml = exporter.to_ttx
#       parser = Fontisan::Export::TtxParser.new

#       expect { parser.parse(ttx_xml) }.not_to raise_error

#       parsed_data = parser.parse(ttx_xml)
#       expect(parsed_data).to be_a(Hash)
#       expect(parsed_data).to have_key(:glyph_order)
#       expect(parsed_data).to have_key(:tables)
#     end

#     it "preserves glyph order in round-trip" do
#       font = Fontisan::FontLoader.load(ttf_path)
#       exporter = Fontisan::Export::Exporter.new(font, ttf_path)

#       ttx_xml = exporter.to_ttx
#       parser = Fontisan::Export::TtxParser.new
#       parsed_data = parser.parse(ttx_xml)

#       expect(parsed_data[:glyph_order].length).to eq(6)
#       expect(parsed_data[:glyph_order][0][:name]).to eq(".notdef")
#       expect(parsed_data[:glyph_order][4][:name]).to eq("period")
#     end

#     it "preserves head table data in round-trip" do
#       font = Fontisan::FontLoader.load(ttf_path)
#       exporter = Fontisan::Export::Exporter.new(font, ttf_path)

#       ttx_xml = exporter.to_ttx(tables: ["head"])
#       parser = Fontisan::Export::TtxParser.new
#       parsed_data = parser.parse(ttx_xml)

#       head_data = parsed_data[:tables]["head"]
#       expect(head_data).not_to be_nil
#       expect(head_data[:units_per_em]).to eq(1000)
#     end
#   end

#   describe "with TestOTF font" do
#     let(:font_path) { "spec/fixtures/fonttools/TestOTF.otf" }

#     include_examples "generates valid TTX"

#     it "generates CFF table" do
#       font = Fontisan::FontLoader.load(font_path)
#       exporter = Fontisan::Export::Exporter.new(font, font_path)

#       ttx_xml = exporter.to_ttx(tables: ["CFF"])

#       expect(ttx_xml).to include("<CFF>")
#       expect(ttx_xml).to include("<hexdata>")
#     end

#     it "has correct sfntVersion for OpenType" do
#       font = Fontisan::FontLoader.load(font_path)
#       exporter = Fontisan::Export::Exporter.new(font, font_path)

#       ttx_xml = exporter.to_ttx

#       # OpenType fonts have OTTO signature
#       expect(ttx_xml).to match(/sfntVersion=/)
#     end
#   end

#   describe "selective table export" do
#     let(:font_path) { "spec/fixtures/fonttools/TestTTF.ttf" }

#     it "exports only specified tables" do
#       font = Fontisan::FontLoader.load(font_path)
#       exporter = Fontisan::Export::Exporter.new(font, font_path)

#       ttx_xml = exporter.to_ttx(tables: ["head", "name"])

#       expect(ttx_xml).to include("<head>")
#       expect(ttx_xml).to include("<name>")
#       expect(ttx_xml).not_to include("<hhea>")
#       expect(ttx_xml).not_to include("<maxp>")
#     end

#     it "handles empty table list" do
#       font = Fontisan::FontLoader.load(font_path)
#       exporter = Fontisan::Export::Exporter.new(font, font_path)

#       ttx_xml = exporter.to_ttx(tables: [])
#       doc = Nokogiri::XML(ttx_xml)

#       # Should still have ttFont and GlyphOrder
#       expect(doc.at_xpath("//ttFont")).not_to be_nil
#       expect(doc.at_xpath("//GlyphOrder")).not_to be_nil
#     end
#   end

#   describe "format compatibility" do
#     let(:font_path) { "spec/fixtures/fonttools/TestTTF.ttf" }

#     it "generates XML that matches fonttools structure" do
#       font = Fontisan::FontLoader.load(font_path)
#       exporter = Fontisan::Export::Exporter.new(font, font_path)

#       ttx_xml = exporter.to_ttx
#       doc = Nokogiri::XML(ttx_xml)

#       # Check fonttools-compatible structure
#       expect(doc.at_xpath("//ttFont/@sfntVersion")).not_to be_nil
#       expect(doc.at_xpath("//ttFont/@ttLibVersion")&.value).to eq("4.0")
#       expect(doc.at_xpath("//GlyphOrder")).not_to be_nil
#     end

#     it "uses fonttools-compatible attribute names" do
#       font = Fontisan::FontLoader.load(ttf_path)
#       exporter = Fontisan::Export::Exporter.new(font, ttf_path)

#       ttx_xml = exporter.to_ttx(tables: ["name"])
#       doc = Nokogiri::XML(ttx_xml)

#       # Check attribute names match fonttools convention
#       namerecord = doc.at_xpath("//namerecord")
#       expect(namerecord["nameID"]).not_to be_nil
#       expect(namerecord["platformID"]).not_to be_nil
#       expect(namerecord["platEncID"]).not_to be_nil
#       expect(namerecord["langID"]).not_to be_nil
#     end
#   end
# end
