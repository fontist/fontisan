# frozen_string_literal: true

require "spec_helper"

# Break-parity round 3 (fontist/fontisan#156): inputs that used to make the
# native and ffi tiers answer differently from the Ruby tier. Each example states
# the Ruby tier's contract and holds on all three tiers.
RSpec.describe "break parity across tiers" do
  include TierParity

  let(:fixtures) { File.expand_path("../fixtures", __dir__) }
  let(:derived) { File.expand_path("../../corpus/derived", __dir__) }
  let(:ttf) { File.join(fixtures, "fonttools", "TestTTF.ttf") }
  let(:ttc) { File.join(fixtures, "fonttools", "TestTTC.ttc") }
  let(:variable) { File.join(fixtures, "fonts", "MonaSansVF", "MonaSansMonoVF[wght].ttf") }

  TierParity::TIERS.each do |tier|
    describe "the #{tier} tier" do
      before { skip_unless_built(tier) }

      # G1: ConvertCommand names a single font's output through MultiFormatOutput.
      describe "convert output naming" do
        it "adds the target extension to an output without one" do
          Dir.mktmpdir do |dir|
            result = with_engine(tier) { Fontisan::Reference.convert(ttf, output: File.join(dir, "foo"), to: :ttf) }
            expect(result[:output_path]).to eq(File.join(dir, "foo.ttf"))
            expect(File.file?(File.join(dir, "foo.ttf"))).to be(true)
            expect(File.exist?(File.join(dir, "foo"))).to be(false)
          end
        end

        it "writes beside an existing directory named as the output" do
          Dir.mktmpdir do |dir|
            Dir.mkdir(File.join(dir, "dd"))
            result = with_engine(tier) { Fontisan::Reference.convert(ttf, output: File.join(dir, "dd"), to: :ttf) }
            expect(result[:output_path]).to eq(File.join(dir, "dd.ttf"))
            expect(File.directory?(File.join(dir, "dd"))).to be(true)
          end
        end

        it "keeps an output that already has the target extension" do
          Dir.mktmpdir do |dir|
            result = with_engine(tier) { Fontisan::Reference.convert(ttf, output: File.join(dir, "o.ttf"), to: :ttf) }
            expect(result[:output_path]).to eq(File.join(dir, "o.ttf"))
          end
        end
      end

      # G2: only the Symbol modes are valid.
      it "rejects the string mode \"full\" with ArgumentError" do
        result = with_engine(tier) { failure { Fontisan::Reference.read(ttf, mode: "full") } }
        expect(result).to eq([ArgumentError, 'Invalid mode: "full". Valid modes are: :metadata, :full'])
      end

      it "accepts the Symbol mode :full" do
        expect(with_engine(tier) { Fontisan::Reference.read(ttf, mode: :full) }).not_to be_nil
      end

      # G3: the axis error keeps its class and its axis/reason message.
      it "raises InvalidAxisError for an unknown axis" do
        result = with_engine(tier) { failure { Fontisan::Reference.instance(variable, coords: { "zzzz" => 1 }) } }
        expect(result).to eq([Fontisan::InvalidAxisError, "Invalid variation axis 'zzzz': font has axes wght"])
      end

      # G4: the engine's Debug text of an InvalidFont error never reaches the caller.
      {
        "malformed-woff-corrupt-deflate.woff" => "woff: zlib stream is corrupt or too long",
        "malformed-woff2-corrupt-brotli.woff2" => "Invalid WOFF2 file: woff: brotli stream is corrupt",
      }.each do |name, message|
        it "converts #{name} to InvalidFontError with the bare message" do
          Dir.mktmpdir do |dir|
            result = with_engine(tier) do
              failure { Fontisan::Reference.convert(File.join(derived, name), output: File.join(dir, "o.ttf"), to: :ttf) }
            end
            expect(result).to eq([Fontisan::InvalidFontError, message])
          end
        end
      end

      # G5: an IO failure while extracting is a Fontisan::Error, as UnpackCommand raises it.
      it "wraps an output directory that cannot be made in Fontisan::Error" do
        result = with_engine(tier) { failure { Fontisan::Reference.extract(ttc, index: 0, output_dir: "") } }
        expect(result[0]).to eq(Fontisan::Error)
        expect(result[1]).to start_with("Unexpected error during unpacking: No such file or directory")
      end

      context "with an unreadable file" do
        let(:unreadable) do
          dir = Dir.mktmpdir
          File.join(dir, "u.ttf").tap { |f| File.write(f, "x") && File.chmod(0, f) }
        end

        after { FileUtils.rm_rf(File.dirname(unreadable)) }

        before { skip "permissions are not enforced for this user" if File.readable?(unreadable) }

        it "wraps the read failure of extract in Fontisan::Error" do
          out = Dir.mktmpdir
          result = with_engine(tier) { failure { Fontisan::Reference.extract(unreadable, index: 0, output_dir: out) } }
          expect(result[0]).to eq(Fontisan::Error)
          expect(result[1]).to start_with("Unexpected error during unpacking: Permission denied")
        ensure
          FileUtils.rm_rf(out)
        end

        # G6
        it "wraps the read failure of audit in Fontisan::Error" do
          result = with_engine(tier) { failure { Fontisan::Reference.audit(unreadable) } }
          expect(result[0]).to eq(Fontisan::Error)
          expect(result[1]).to start_with("Failed to load font: Permission denied")
        end
      end

      # G7
      it "rejects a nil path in a scan list with the Reference TypeError" do
        result = with_engine(tier) { failure { Fontisan::Reference.scan([ttf, nil]) } }
        expect(result).to eq([TypeError, "Reference operations take a file path, got NilClass"])
      end
    end
  end
end
