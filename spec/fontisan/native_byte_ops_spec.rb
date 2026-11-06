# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# Card 2f: convert, extract, instance and subset through the native gates.
# Needs the built extension (`bundle exec rake compile`); a missing extension
# fails the examples, it never skips them.
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

  def native(&) = with_engine("native", &)
  def ruby(&) = with_engine("ruby", strict: false, &)

  it "has the extension built" do
    expect(Fontisan::Native.available?).to be(true)
  end

  describe "convert" do
    it "writes the same bytes and result hash as Ruby, served natively" do
      Dir.mktmpdir do |dir|
        n = native do
          Fontisan::Reference.convert(ttf, to: :woff2, output: File.join(dir, "n.woff2"), timestamp: stamp)
            .tap { expect(Fontisan::Engine.served_by(:convert)).to eq(:native) }
        end
        r = ruby { Fontisan::Reference.convert(ttf, to: :woff2, output: File.join(dir, "r.woff2"), timestamp: stamp) }
        expect(File.binread(File.join(dir, "n.woff2"))).to eq(File.binread(File.join(dir, "r.woff2")))
        expect(n.except(:output_path)).to eq(r.except(:output_path))
      end
    end

    it "serves Fontisan.convert natively too" do
      Dir.mktmpdir do |dir|
        native do
          Fontisan.convert(ttf, to: :woff, output: File.join(dir, "o.woff"))
          expect(Fontisan::Engine.served_by(:convert)).to eq(:native)
        end
      end
    end

    it "converts a collection to a collection natively and matches Ruby" do
      Dir.mktmpdir do |dir|
        n = native do
          Fontisan::Reference.convert(ttc, to: :otc, output: File.join(dir, "n.otc"), timestamp: stamp)
            .tap { expect(Fontisan::Engine.served_by(:convert)).to eq(:native) }
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
        native do
          result = Fontisan::Reference.convert(otc, to: :ttc, output: File.join(dir, "o.ttc"))
          expect(Fontisan::Engine.served_by(:convert)).to eq(:ruby)
          expect(result[:source_format]).to eq(:otc)
        end
      end
    end

    it "routes the options the engine does not serve to Ruby" do
      Dir.mktmpdir do |dir|
        native do
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
        native do
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
    it "extracts the same member as Ruby, served natively" do
      Dir.mktmpdir do |dir|
        n = native do
          Fontisan::Reference.extract(ttc, index: 1, output_dir: File.join(dir, "n"))
            .tap { expect(Fontisan::Engine.served_by(:extract)).to eq(:native) }
        end
        r = ruby { Fontisan::Reference.extract(ttc, index: 1, output_dir: File.join(dir, "r")) }
        expect(File.basename(n)).to eq(File.basename(r))
        expect(File.binread(n)).to eq(File.binread(r))
      end
    end
  end

  describe "instance and subset" do
    it "instances a variable font identically to Ruby, served natively" do
      coords = { "wght" => 700 }
      n = native do
        Fontisan::Reference.instance(vf, coords: coords)
          .tap { expect(Fontisan::Engine.served_by(:instance)).to eq(:native) }
      end
      expect(n).to eq(ruby { Fontisan::Reference.instance(vf, coords: coords) })
    end

    it "subsets identically to Ruby, served natively" do
      n = native do
        Fontisan::Reference.subset(ttf, unicodes: [32, 46])
          .tap { expect(Fontisan::Engine.served_by(:subset)).to eq(:native) }
      end
      expect(n).to eq(ruby { Fontisan::Reference.subset(ttf, unicodes: [32, 46]) })
    end

    it "raises Ruby's error for characters the font lacks" do
      message = ruby do
        Fontisan::Reference.subset(ttf, unicodes: [0x10FFFF])
      rescue StandardError => e
        [e.class, e.message]
      end
      native do
        got = begin
          Fontisan::Reference.subset(ttf, unicodes: [0x10FFFF])
        rescue StandardError => e
          [e.class, e.message]
        end
        expect(got).to eq(message)
        expect(Fontisan::Engine.served_by(:subset)).to eq(:native)
      end
    end
  end

  describe "object-based entry points" do
    %w[native auto].each do |selection|
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

  # TODO(2f ffi): once card 2d is merged, repeat these examples with
  # FONTISAN_ENGINE=ffi and served_by == :ffi (the ffi tier takes the same
  # option checks as Native.supports_options?).
end
