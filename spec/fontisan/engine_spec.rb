# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Fontisan::Engine do
  let(:dir) { File.expand_path("../fixtures/fonttools", __dir__) }
  let(:ttf) { File.join(dir, "TestTTF.ttf") }
  let(:ttc) { File.join(dir, "TestTTC.ttc") }
  let(:woff) { File.join(dir, "TestWOFF.woff") }
  let(:vf) do
    File.expand_path("../fixtures/fonts/MonaSansVF/MonaSansVF[wght,opsz].ttf",
                     __dir__)
  end
  let(:out) { Dir.mktmpdir("engine-spec") }
  # A tier that is available, serves every operation except for paths matching
  # +skip+, and answers with a marker instead of doing any work.
  let(:fake_class) do
    Class.new do
      attr_reader :calls

      def initialize(skip: nil, without: [])
        @skip = skip
        @without = without
        @calls = []
      end

      def available? = true

      def supports?(operation, path = nil)
        !@without.include?(operation) && !(@skip && path.to_s.match?(@skip))
      end

      def call(operation, *args, **_kwargs)
        @calls << [operation, args.first]
        operation == :scan ? [{ "path" => args.first.first.to_s }] : [:marker]
      end
    end
  end
  # Every Reference operation with arguments cheap enough to run for real.
  let(:op_calls) do
    {
      read: -> { Fontisan::Reference.read(ttf) },
      outline_hashes: -> { Fontisan::Reference.outline_hashes(ttf) },
      audit: -> { Fontisan::Reference.audit(ttf) },
      audit_dir: -> { Fontisan::Reference.audit_dir(File.join(out, "d")) },
      scan: -> { Fontisan::Reference.scan([ttf]) },
      convert: lambda {
        Fontisan::Reference.convert(ttf, to: :woff,
                                         output: File.join(out, "o.woff"))
      },
      extract: lambda {
        Fontisan::Reference.extract(ttc, index: 0, output_dir: out)
      },
      instance: -> { Fontisan::Reference.instance(vf, coords: { "wght" => 400 }) },
      glyph_ids: -> { Fontisan::Reference.glyph_ids(ttf, text: ".") },
      subset: -> { Fontisan::Reference.subset(ttf, text: ".") },
    }
  end

  # These examples use fake tiers; the real extension (spec/fontisan/native_spec.rb)
  # must not answer, so it is hidden even when built.
  before do
    allow(Fontisan::Native).to receive(:load_extension).and_raise(LoadError)
    Fontisan::Native.reset!
  end

  around do |example|
    saved = ENV.to_h.slice("FONTISAN_ENGINE", "FONTISAN_ENGINE_STRICT", "FONTISAN_CDYLIB")
    ENV.delete("FONTISAN_ENGINE")
    ENV.delete("FONTISAN_ENGINE_STRICT")
    # These examples assume no ffi library; a built one must not leak in.
    ENV["FONTISAN_CDYLIB"] = File.join(Dir.tmpdir, "no-such-fontisan-lib")
    described_class.reset!
    FileUtils.mkdir_p(File.join(out, "d"))
    FileUtils.cp(ttf, File.join(out, "d"))
    example.run
  ensure
    ENV.delete("FONTISAN_ENGINE")
    ENV.delete("FONTISAN_ENGINE_STRICT")
    ENV.delete("FONTISAN_CDYLIB")
    ENV.update(saved)
    described_class.reset!
    FileUtils.rm_rf(out)
  end

  def configure(engine, strict: false)
    ENV["FONTISAN_ENGINE"] = engine
    ENV["FONTISAN_ENGINE_STRICT"] = strict ? "1" : nil
  end

  describe "default" do
    it "is :ruby for every operation, with nothing configured" do
      op_calls.each do |operation, call|
        call.call
        expect(described_class.served_by(operation)).to eq(:ruby), "operation #{operation}"
      end
      expect(described_class.counters.keys).to eq([:ruby])
    end

    it "has no native or ffi tier available when the extensions do not load" do
      expect(Fontisan::Native.available?).to be(false)
      expect(Fontisan::Ffi.available?).to be(false)
    end

    it "keeps Reference output free of served_by" do
      expect(Fontisan::Reference.scan([ttf]).first).not_to have_key("served_by")
    end
  end

  describe "with no native or ffi tier" do
    %w[ruby auto].each do |value|
      [false, true].each do |strict|
        it "FONTISAN_ENGINE=#{value} strict=#{strict} serves every operation from ruby" do
          configure(value, strict: strict)
          op_calls.each do |operation, call|
            call.call
            expect(described_class.served_by(operation)).to eq(:ruby), "operation #{operation}"
          end
        end
      end
    end

    %w[native ffi].each do |value|
      it "FONTISAN_ENGINE=#{value} falls back to ruby when not strict" do
        configure(value)
        op_calls.each do |operation, call|
          call.call
          expect(described_class.served_by(operation)).to eq(:ruby), "operation #{operation}"
        end
      end

      it "FONTISAN_ENGINE=#{value} strict raises at setup, before any work" do
        configure(value, strict: true)
        op_calls.each_value do |call|
          expect(&call).to raise_error(described_class::TierUnavailable, /#{value}/)
        end
        expect(described_class.counters).to eq({})
      end
    end

    it "rejects an unknown FONTISAN_ENGINE" do
      configure("rust")
      expect { Fontisan::Reference.read(ttf) }
        .to raise_error(described_class::ConfigError, /rust/)
    end

    it "treats the value case-insensitively" do
      configure("RUBY")
      Fontisan::Reference.read(ttf)
      expect(described_class.served_by(:read)).to eq(:ruby)
    end
  end

  describe "with a fake native tier" do
    let(:native) { fake_class.new(skip: /\.woff\z/) }

    before { described_class.register(:native, native) }

    [false, true].each do |strict|
      it "serves every operation from native when forced (strict=#{strict})" do
        configure("native", strict: strict)
        op_calls.each do |operation, call|
          call.call
          expect(described_class.served_by(operation)).to eq(:native), "operation #{operation}"
        end
        expect(native.calls.map(&:first)).to match_array(op_calls.keys)
      end

      it "serves every operation from native under auto (strict=#{strict})" do
        configure("auto", strict: strict)
        op_calls.each do |operation, call|
          call.call
          expect(described_class.served_by(operation)).to eq(:native), "operation #{operation}"
        end
      end
    end

    it "still serves ruby when ruby is forced" do
      configure("ruby", strict: true)
      Fontisan::Reference.read(ttf)
      expect(described_class.served_by(:read)).to eq(:ruby)
      expect(native.calls).to be_empty
    end

    it "routes a path the tier cannot serve to ruby, even when strict" do
      configure("native", strict: true)
      Fontisan::Reference.read(woff)
      expect(described_class.served_by(:read)).to eq(:ruby)
      Fontisan::Reference.read(ttf)
      expect(described_class.served_by(:read)).to eq(:native)
    end

    it "counts calls per tier and operation" do
      configure("native", strict: true)
      2.times { Fontisan::Reference.read(ttf) }
      Fontisan::Reference.read(woff)
      expect(described_class.counters)
        .to eq(native: { read: 2 }, ruby: { read: 1 })
    end

    it "forced ffi strict still raises when only native exists" do
      configure("ffi", strict: true)
      expect { Fontisan::Reference.read(ttf) }
        .to raise_error(described_class::TierUnavailable, /ffi/)
    end

    it "gives per-row served_by for a mixed scan, in input order" do
      configure("native", strict: true)
      rows = described_class.scan([ttf, woff])
      expect(rows.map { |r| r["served_by"] }).to eq(%w[native ruby])
      expect(rows.last["format"]).to eq("woff")
      expect(Fontisan::Reference.scan([ttf, woff]).size).to eq(2)
    end

    it "gives per-row served_by for a mixed audit_dir" do
      described_class.register(
        :native, fake_class.new(skip: /\.woff\z/, without: [:audit_dir])
      )
      FileUtils.cp(woff, File.join(out, "d"))
      configure("native", strict: true)
      entries = described_class.audit_dir(File.join(out, "d"))
      expect(entries.to_h { |e| [e["path"], e["served_by"]] })
        .to eq("TestTTF.ttf" => "native", "TestWOFF.woff" => "ruby")
    end
  end

  describe "auto order" do
    it "prefers native, then ffi, then ruby" do
      configure("auto")
      described_class.register(:ffi, fake_class.new)
      Fontisan::Reference.read(ttf)
      expect(described_class.served_by(:read)).to eq(:ffi)

      described_class.register(:native, fake_class.new)
      Fontisan::Reference.read(ttf)
      expect(described_class.served_by(:read)).to eq(:native)
    end
  end

  describe "a failing loader" do
    [NameError, NoMethodError, LoadError, NotImplementedError,
     RuntimeError].each do |error|
      it "falls back without raising #{error}" do
        allow(Fontisan::Native).to receive(:load_extension).and_raise(error)
        configure("native")
        expect(Fontisan::Reference.read(ttf)).not_to be_empty
        expect(described_class.served_by(:read)).to eq(:ruby)
      end

      it "raises TierUnavailable at setup when strict (#{error})" do
        allow(Fontisan::Native).to receive(:load_extension).and_raise(error)
        configure("native", strict: true)
        expect { Fontisan::Reference.read(ttf) }
          .to raise_error(described_class::TierUnavailable)
      end
    end

    it "treats an ABI mismatch as unavailable" do
      allow(Fontisan::Native).to receive(:load_extension)
      allow(Fontisan::Native).to receive(:extension_abi_version).and_return(99)
      expect(Fontisan::Native.available?).to be(false)
    end

    it "falls back when a registered tier's probe raises NameError" do
      broken = Class.new do
        def available? = raise(NameError, "uninitialized constant FontisanNative")
      end
      described_class.register(:native, broken.new)
      configure("auto")
      Fontisan::Reference.read(ttf)
      expect(described_class.served_by(:read)).to eq(:ruby)
    end

    it "falls back per operation when supports? raises" do
      flaky = fake_class.new
      allow(flaky).to receive(:supports?).and_raise(NameError)
      described_class.register(:native, flaky)
      configure("native", strict: true)
      Fontisan::Reference.read(ttf)
      expect(described_class.served_by(:read)).to eq(:ruby)
    end
  end

  describe "FONTISAN_MODE and FONTISAN_LAZY" do
    it "are not read by the engine" do
      source = File.read(File.expand_path("../../lib/fontisan/engine.rb", __dir__))
      names = source.scan(/ENV(?:\.fetch)?[\[(]\s*"(\w+)"/).flatten.uniq
      expect(names).to contain_exactly("FONTISAN_ENGINE", "FONTISAN_ENGINE_STRICT")
    end
  end
end
