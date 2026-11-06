# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "rbconfig"
require "open3"

RSpec.describe Fontisan::Native do
  let(:fixtures) { File.expand_path("../fixtures/fonttools", __dir__) }
  let(:ttf) { File.join(fixtures, "TestTTF.ttf") }
  let(:woff) { File.join(fixtures, "TestWOFF.woff") }
  let(:ttc) { File.join(fixtures, "TestTTC.ttc") }
  let(:dfont) { File.join(fixtures, "TestDFONT.dfont") }

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

  def ruby_result(&)
    with_engine("ruby", strict: false, &)
  end

  describe "extconf without cargo" do
    it "writes a no-op Makefile and leaves a working :ruby gem" do
      Dir.mktmpdir("noext") do |dir|
        extconf = File.expand_path("../../ext/fontisan_native/extconf.rb", __dir__)
        work = File.join(dir, "build")
        FileUtils.mkdir_p(work)
        # Keep the real ruby (and its DLL directory on Windows) on PATH; drop only
        # the directories that provide cargo.
        cargo_names = ["cargo", *ENV.fetch("PATHEXT", "").split(";").map { |e| "cargo#{e.downcase}" }]
        path = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).reject do |d|
          cargo_names.any? { |n| File.file?(File.join(d, n)) }
        end
        ruby = RbConfig.ruby
        env = { "PATH" => path.join(File::PATH_SEPARATOR), "RUBYOPT" => nil, "RUBYLIB" => nil, "BUNDLE_GEMFILE" => nil }
        out = IO.popen(env, [ruby, extconf], chdir: work, err: %i[child out], &:read)
        expect($?).to be_success, out
        expect(out).to include("skipping the native extension (cargo not found)")
        makefile = File.read(File.join(work, "Makefile"))
        expect(makefile).to match(/^all:/)
        expect(Dir.children(work)).to eq(["Makefile"])
      end
    end
  end

  describe "an extension that is present but unusable" do
    def probe_stderr(dir, lib: File.expand_path("../../lib", __dir__))
      script = "require 'fontisan'; 2.times { Fontisan::Native.reset!; Fontisan::Native.available? }; " \
               "puts Fontisan::Native.available?.inspect"
      out, err, = Open3.capture3({ "RUBYOPT" => nil }, RbConfig.ruby, "-I", lib, "-I", dir, "-e", script)
      [out.strip, err]
    end

    it "warns once and still falls back" do
      Dir.mktmpdir("badext") do |dir|
        FileUtils.mkdir_p(File.join(dir, "fontisan", "native"))
        File.write(File.join(dir, "fontisan", "native", "fontisan_native.rb"), "# loads, but reports no ABI\n")
        out, err = probe_stderr(dir)
        expect(out).to eq("false")
        expect(err.scan("native extension is present but did not load").size).to eq(1)
      end
    end

    it "stays quiet when there is no extension file at all" do
      allow(described_class).to receive_messages(probe: false, extension_present?: false)
      described_class.reset!
      expect { expect(described_class.available?).to be(false) }.not_to output.to_stderr
    ensure
      described_class.reset!
    end
  end

  context "with the extension built" do
    before do
      skip "extension not built (bundle exec rake compile)" unless described_class.available?
    end

    it "reports the ABI the gem expects" do
      expect(described_class.extension_abi_version).to eq(described_class::ABI_VERSION)
    end

    it "serves read, audit, scan and audit_dir with the Ruby tier's output, tagged :native" do
      calls = {
        read: -> { Fontisan::Reference.read(ttf) },
        audit: -> { Fontisan::Reference.audit(ttf, validate: true) },
        scan: -> { Fontisan::Reference.scan([ttf, woff, ttc]) },
        audit_dir: -> { Fontisan::Reference.audit_dir(fixtures) },
      }
      expected = ruby_result { calls.transform_values(&:call) }
      with_engine("native") do
        calls.each do |operation, call|
          expect(call.call).to eq(expected.fetch(operation)), operation.to_s
          expect(Fontisan::Engine.served_by(operation)).to eq(:native), operation.to_s
        end
      end
    end

    it "routes dfont to :ruby in strict mode, for every operation and inside a mixed scan" do
      with_engine("native") do
        Fontisan::Reference.read(dfont)
        Fontisan::Reference.audit(dfont)
        expect(Fontisan::Engine.counters).to eq(ruby: { read: 1, audit: 1 })
        rows = Fontisan::Engine.scan([ttf, dfont, woff])
        expect(rows.to_h { |r| [File.basename(r["path"]), r["served_by"]] })
          .to eq("TestTTF.ttf" => "native", "TestDFONT.dfont" => "ruby", "TestWOFF.woff" => "native")
      end
    end

    it "tags a mixed audit_dir per file" do
      Dir.mktmpdir("mixed") do |dir|
        FileUtils.cp([ttf, dfont, woff], dir)
        with_engine("native") do
          entries = Fontisan::Engine.audit_dir(dir)
          expect(entries.to_h { |e| [e["path"], e["served_by"]] })
            .to eq("TestTTF.ttf" => "native", "TestDFONT.dfont" => "ruby", "TestWOFF.woff" => "native")
          expect(entries.map { |e| e.except("served_by") }).to eq(ruby_result { Fontisan::Reference.audit_dir(dir) })
        end
      end
    end

    it "tags a file handed back to Ruby as :ruby when the engine reports native separators (Windows)" do
      Dir.mktmpdir("winsep") do |dir|
        FileUtils.cp([ttf, dfont], dir)
        stub_const("File::ALT_SEPARATOR", "\\")
        with_engine("native") do
          original = described_class.method(:native_audit_dir_rows)
          allow(described_class).to receive(:native_audit_dir_rows) do |*args|
            original.call(*args).map { |row| row.merge("path" => row["path"].sub(%r{/([^/]+)\z}, '\\\\\1')) }
          end
          entries = Fontisan::Engine.audit_dir(dir)
          expect(entries.to_h { |e| [e["path"], e["served_by"]] })
            .to eq("TestTTF.ttf" => "native", "TestDFONT.dfont" => "ruby")
        end
      end
    end

    it "serves what the extension cannot honour from Ruby (profile validation)" do
      with_engine("native") do
        Fontisan::Reference.audit(ttf, validate: "web")
        expect(Fontisan::Engine.served_by(:audit)).to eq(:ruby)
      end
    end

    it "rebuilds the Ruby tier's error class, message and cause chain" do
      Dir.mktmpdir("bad") do |dir|
        bad = File.join(dir, "bad.ttf")
        File.binwrite(bad, File.binread(ttf)[0, 100])
        want = ruby_result do
          Fontisan::Reference.read(bad)
        rescue StandardError => e
          [e.class, e.message, e.cause&.class, e.cause&.message]
        end
        with_engine("native") do
          got = begin
            Fontisan::Reference.read(bad)
          rescue StandardError => e
            [e.class, e.message, e.cause&.class, e.cause&.message]
          end
          expect(got).to eq(want)
          expect(Fontisan::Engine.served_by(:read)).to eq(:native)
        end
      end
    end

    it "runs a threaded scan" do
      want = ruby_result { Fontisan::Reference.scan([ttf, woff, ttc]) }
      with_engine("native") do
        results = Array.new(8) { Thread.new { Fontisan::Reference.scan([ttf, woff, ttc]) } }.map(&:value)
        expect(results).to all(eq(want))
      end
    end

    it "keeps another Ruby thread running during a long native call (GVL released)" do
      ticks = 0
      ticker = Thread.new do
        loop do
          sleep 0.01
          ticks += 1
        end
      end
      sleep 0.05
      before = ticks
      described_class.native_selftest_block(400)
      during = ticks - before
      ticker.kill
      expect(during).to be > 10
    end

    it "turns a Rust panic into a Ruby error" do
      expect { described_class.native_selftest_panic }
        .to raise_error(described_class::Panic, /seeded panic/)
      expect(described_class.native_read(ttf, true, true)).to be_a(Array)
    end

    it "exposes convert, extract, instance and subset as byte operations" do
      expect(described_class.native_convert(ttf, 3, 0)).to start_with("wOF2")
      name, data = described_class.native_extract(ttc, 0)
      expect([name, data.bytesize]).to match([a_string_ending_with(".ttf"), be > 0])
      expect(described_class.native_subset(ttf, [0, 1], "web")).to be_a(String)
    end
  end
end
