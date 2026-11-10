# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "timeout"
require "fileutils"

# Cards 2f and 2f-ffi: convert, extract, instance and subset through the
# native and ffi gates. Needs the built extension (`bundle exec rake compile`)
# and, for ffi, the built library (`rake cdylib:build`, FONTISAN_CDYLIB); a
# missing tier skips the examples (the tier jobs build it).
RSpec.describe "native byte ops" do
  let(:fixtures) { File.expand_path("../fixtures", __dir__) }
  let(:ttf) { File.join(fixtures, "fonttools", "TestTTF.ttf") }
  let(:ttc) { File.join(fixtures, "fonttools", "TestTTC.ttc") }
  let(:vf) { File.join(fixtures, "fonts", "MonaSansVF", "MonaSansMonoVF[wght].ttf") }
  let(:stamp) { 1_735_689_600 }

  def with_engine(selection, strict: true)
    saved = ENV.to_h.slice("FONTISAN_ENGINE", "FONTISAN_ENGINE_STRICT")
    ENV["FONTISAN_ENGINE"] = selection
    ENV["FONTISAN_ENGINE_STRICT"] = strict ? "1" : nil
    Fontisan::Engine.reset!
    yield
  ensure
    ENV.delete("FONTISAN_ENGINE")
    ENV.delete("FONTISAN_ENGINE_STRICT")
    ENV.update(saved)
    Fontisan::Engine.reset!
  end

  def ruby(&) = with_engine("ruby", strict: false, &)

  { native: Fontisan::Native, ffi: Fontisan::Ffi }.each do |name, mod|
    describe "the #{name} tier" do
      let(:tier_name) { name.to_s }

      # Same convention as native_spec/ffi_spec: the plain rake job has no Rust
      # toolchain, so an unbuilt tier skips. The tier jobs build it and run these.
      before { skip "#{name} tier not built (rake compile / rake cdylib:build)" unless mod.available? }

      def tier(&) = with_engine(tier_name, &)

      it "is available" do
        expect(mod.available?).to be(true)
      end

      describe "convert" do
        it "writes the same bytes and result hash as Ruby, served by the tier" do
          Dir.mktmpdir do |dir|
            n = tier do
              Fontisan::Reference.convert(ttf, to: :woff2, output: File.join(dir, "n.woff2"), timestamp: stamp)
                .tap { expect(Fontisan::Engine.served_by(:convert)).to eq(name) }
            end
            r = ruby { Fontisan::Reference.convert(ttf, to: :woff2, output: File.join(dir, "r.woff2"), timestamp: stamp) }
            expect(File.binread(File.join(dir, "n.woff2"))).to eq(File.binread(File.join(dir, "r.woff2")))
            expect(n.except(:output_path)).to eq(r.except(:output_path))
          end
        end

        it "serves Fontisan.convert by the tier too" do
          Dir.mktmpdir do |dir|
            tier do
              Fontisan.convert(ttf, to: :woff, output: File.join(dir, "o.woff"))
              expect(Fontisan::Engine.served_by(:convert)).to eq(name)
            end
          end
        end

        it "converts a collection to a collection by the tier and matches Ruby" do
          Dir.mktmpdir do |dir|
            n = tier do
              Fontisan::Reference.convert(ttc, to: :otc, output: File.join(dir, "n.otc"), timestamp: stamp)
                .tap { expect(Fontisan::Engine.served_by(:convert)).to eq(name) }
            end
            r = ruby { Fontisan::Reference.convert(ttc, to: :otc, output: File.join(dir, "r.otc"), timestamp: stamp) }
            expect(File.binread(File.join(dir, "n.otc"))).to eq(File.binread(File.join(dir, "r.otc")))
            expect(n.except(:output_path)).to eq(r.except(:output_path))
          end
        end

        it "keeps an .otc collection input on Ruby (the engine cannot take the extension hint)" do
          Dir.mktmpdir do |dir|
            otc = File.join(dir, "in.otc")
            FileUtils.cp(ttc, otc)
            tier do
              result = Fontisan::Reference.convert(otc, to: :ttc, output: File.join(dir, "o.ttc"))
              expect(Fontisan::Engine.served_by(:convert)).to eq(:ruby)
              expect(result[:source_format]).to eq(:otc)
            end
          end
        end

        it "routes the options the engine does not serve to Ruby" do
          Dir.mktmpdir do |dir|
            tier do
              Fontisan::Reference.convert(vf, to: :ttf, output: File.join(dir, "a.ttf"), coordinates: "wght=700")
              expect(Fontisan::Engine.served_by(:convert)).to eq(:ruby)
              Fontisan::Reference.convert(ttf, to: "woff,woff2", output: File.join(dir, "b"))
              expect(Fontisan::Engine.served_by(:convert)).to eq(:ruby)
              Fontisan::Reference.convert(ttf, to: :otf, output: File.join(dir, "c.otf"), preserve_hints: true)
              expect(Fontisan::Engine.served_by(:convert)).to eq(:ruby)
            end
          end
        end

        it "routes a collection converted to a non-collection format to Ruby, with Ruby's error" do
          Dir.mktmpdir do |dir|
            error = ruby do
              Fontisan::Reference.convert(ttc, to: :ttf, output: File.join(dir, "r.ttf"))
            rescue StandardError => e
              [e.class, e.message]
            end
            tier do
              got = begin
                Fontisan::Reference.convert(ttc, to: :ttf, output: File.join(dir, "n.ttf"))
              rescue StandardError => e
                [e.class, e.message]
              end
              expect(Fontisan::Engine.served_by(:convert)).to eq(:ruby)
              expect(got).to eq(error)
            end
          end
        end
      end

      describe "extract" do
        it "extracts the same member as Ruby, served by the tier" do
          Dir.mktmpdir do |dir|
            n = tier do
              Fontisan::Reference.extract(ttc, index: 1, output_dir: File.join(dir, "n"))
                .tap { expect(Fontisan::Engine.served_by(:extract)).to eq(name) }
            end
            r = ruby { Fontisan::Reference.extract(ttc, index: 1, output_dir: File.join(dir, "r")) }
            expect(File.basename(n)).to eq(File.basename(r))
            expect(File.binread(n)).to eq(File.binread(r))
          end
        end

        # fontisan-rs 0687123 (head-offset fix): a TTC whose head table offset
        # overflows must not hang or write a huge file. Ruby's extract is not run
        # on it: it would write about 4 GiB.
        it "extracts the head-offset fuzz TTC without a hang or a huge write" do
          fuzz = File.expand_path("../../corpus/derived/malformed-fuzz-ttc-head-offset.ttc", __dir__)
          Dir.mktmpdir do |dir|
            Timeout.timeout(60) do
              tier do
                Fontisan::Reference.extract(fuzz, index: 0, output_dir: dir)
              rescue StandardError => e
                expect(e.message.bytesize).to be < 1_000
              end
            end
            expect(Dir.glob(File.join(dir, "**", "*")).sum { |f| File.file?(f) ? File.size(f) : 0 }).to be < 1_048_576
          end
        end
      end

      describe "instance and subset" do
        it "instances a variable font identically to Ruby, served by the tier" do
          coords = { "wght" => 700 }
          n = tier do
            Fontisan::Reference.instance(vf, coords: coords)
              .tap { expect(Fontisan::Engine.served_by(:instance)).to eq(name) }
          end
          expect(n).to eq(ruby { Fontisan::Reference.instance(vf, coords: coords) })
        end

        it "subsets identically to Ruby, served by the tier" do
          n = tier do
            Fontisan::Reference.subset(ttf, unicodes: [32, 46])
              .tap { expect(Fontisan::Engine.served_by(:subset)).to eq(name) }
          end
          expect(n).to eq(ruby { Fontisan::Reference.subset(ttf, unicodes: [32, 46]) })
        end

        it "raises Ruby's error for characters the font lacks" do
          message = ruby do
            Fontisan::Reference.subset(ttf, unicodes: [0x10FFFF])
          rescue StandardError => e
            [e.class, e.message]
          end
          tier do
            got = begin
              Fontisan::Reference.subset(ttf, unicodes: [0x10FFFF])
            rescue StandardError => e
              [e.class, e.message]
            end
            expect(got).to eq(message)
            expect(Fontisan::Engine.served_by(:subset)).to eq(name)
          end
        end
      end
    end
  end

  describe "object-based entry points" do
    %w[native ffi auto].each do |selection|
      it "reports :ruby for Subset::Builder and Variable::Instancer under #{selection}" do
        with_engine(selection) do
          font = Fontisan::FontLoader.load(ttf, mode: :full, lazy: false)
          gids = font.table("cmap").unicode_mappings.values_at(32, 46).compact
          Fontisan::Subset::Builder.new(font, gids, Fontisan::Subset::Options.new(profile: "web")).build
          vfont = Fontisan::FontLoader.load(vf, mode: :full, lazy: false)
          Fontisan::Variable::Instancer.new(vfont).instance({ "wght" => 700.0 })
          expect(Fontisan::Engine.served_by(:subset)).to eq(:ruby)
          expect(Fontisan::Engine.served_by(:instance)).to eq(:ruby)
          expect(Fontisan::Engine.counters.keys).to eq([:ruby])
        end
      end
    end

    it "reports :ruby for them under the ruby tier as well" do
      ruby do
        font = Fontisan::FontLoader.load(ttf, mode: :full, lazy: false)
        Fontisan::Subset::Builder.new(font, [1, 2], Fontisan::Subset::Options.new(profile: "web")).build
        expect(Fontisan::Engine.served_by(:subset)).to eq(:ruby)
      end
    end
  end
end
