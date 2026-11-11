# frozen_string_literal: true

require "spec_helper"

# A malformed font or an unusable output path fails with the same public class on
# every tier: no NoMethodError / IndexError from the Ruby parsers, no
# bare Fontisan::Error from the engine where Ruby raises InvalidFontError, no raw
# Errno from one tier while another wraps it, and no write over the input.
RSpec.describe "malformed input and output paths across tiers" do
  include TierParity

  let(:derived) { File.expand_path("../../corpus/derived", __dir__) }
  let(:fixtures) { File.expand_path("../fixtures", __dir__) }
  let(:ttf) { File.join(fixtures, "fonttools", "TestTTF.ttf") }
  let(:variable) { File.join(fixtures, "fonts", "MonaSansVF", "MonaSansMonoVF[wght].ttf") }
  let(:tmp) { Dir.mktmpdir("tier-malformed") }

  after { FileUtils.remove_entry(tmp) }

  def write_font(name, bytes)
    File.join(tmp, name).tap { |path| File.binwrite(path, bytes) }
  end

  # The font with the byte at +offset+ of its +tag+ table set to 0xFF.
  def with_table_byte(path, tag, offset)
    data = File.binread(path)
    table = (0...data[4, 2].unpack1("n")).map { |i| data[12 + (16 * i), 16].unpack("a4NNN") }.assoc(tag)
    data.dup.tap { |copy| copy.setbyte(table[2] + offset, 0xFF) }
  end

  TierParity::TIERS.each do |tier|
    describe "the #{tier} tier" do
      before { skip_unless_built(tier) }

      %w[malformed-woff-corrupt-deflate.woff malformed-woff2-corrupt-brotli.woff2].each do |name|
        it "fails convert of #{name} with InvalidFontError" do
          result = with_engine(tier) do
            failure { Fontisan.convert(File.join(derived, name), to: :ttf, output: File.join(tmp, "o.ttf")) }
          end
          expect(result.first).to eq(Fontisan::InvalidFontError)
        end

        it "fails instance of #{name} with InvalidFontError" do
          result = with_engine(tier) do
            failure { Fontisan::Reference.instance(File.join(derived, name), coords: { "wght" => 400 }) }
          end
          expect(result.first).to eq(Fontisan::InvalidFontError)
        end
      end

      it "fails instance of a font with a table past the end of the file like convert does" do
        file = File.join(derived, "malformed-bad-table-offset.ttf")
        result = with_engine(tier) { failure { Fontisan::Reference.instance(file, coords: { "wght" => 400 }) } }
        expect(result).to eq([Fontisan::Error, "Conversion failed: Transformation failed: invalid sfnt table directory"])
      end

      [5, 19].each do |offset|
        it "fails instance of a variable font with a damaged gvar (byte #{offset}) with InvalidFontError" do
          file = write_font("gvar.ttf", with_table_byte(variable, "gvar", offset))
          result = with_engine(tier) { failure { Fontisan::Reference.instance(file, coords: { "wght" => 500 }) } }
          expect(result.first).to eq(Fontisan::InvalidFontError)
        end
      end

      describe "convert output path" do
        let(:input) { write_font("in.ttf", File.binread(ttf)) }
        let(:engine) { tier }

        def convert_to(output)
          with_engine(engine) { failure { Fontisan::Reference.convert(input, output: output, to: :ttf) } }
        end

        it "refuses to overwrite the input" do
          expect(convert_to(input).first).to eq(Fontisan::OutputGuard::Refused)
          expect(File.binread(input)).to eq(File.binread(ttf))
        end

        it "refuses a symlink to the input" do
          link = File.join(tmp, "link.ttf")
          File.symlink(input, link)
          expect(convert_to(link).first).to eq(Fontisan::OutputGuard::Refused)
          expect(File.binread(input)).to eq(File.binread(ttf))
        end

        it "refuses a path that reaches the input through .." do
          FileUtils.mkdir_p(File.join(tmp, "sub"))
          expect(convert_to(File.join(tmp, "sub", "..", "in.ttf")).first).to eq(Fontisan::OutputGuard::Refused)
          expect(File.binread(input)).to eq(File.binread(ttf))
        end

        it "raises ArgumentError for a missing output directory" do
          result = convert_to(File.join(tmp, "none", "out.ttf"))
          expect(result).to eq([ArgumentError, "Output directory not found: #{File.join(tmp, 'none')}"])
        end

        it "wraps an output that is a directory in Fontisan::Error" do
          FileUtils.mkdir_p(File.join(tmp, "out.ttf"))
          result = convert_to(File.join(tmp, "out.ttf"))
          expect(result.first).to eq(Fontisan::Error)
          expect(result.last).to start_with("Conversion failed: Transformation failed: ")
        end

        it "writes an output named after the extension to that name, not twice" do
          expect(convert_to(File.join(tmp, ".ttf"))).to be_nil
          expect(Dir.children(tmp)).to include(".ttf")
          expect(Dir.children(tmp)).not_to include(".ttf.ttf")
        end
      end
    end
  end

  describe "Fontisan::OutputGuard" do
    let(:described_class) { Fontisan::OutputGuard }

    it "passes a different file, existing or not" do
      other = File.join(tmp, "other.ttf")
      expect { described_class.check!(ttf, other) }.not_to raise_error
      File.write(other, "x")
      expect { described_class.check!(ttf, other) }.not_to raise_error
    end

    it "refuses the same file" do
      expect { described_class.check!(ttf, ttf) }.to raise_error(described_class::Refused, /refusing to overwrite/)
    end
  end
end
