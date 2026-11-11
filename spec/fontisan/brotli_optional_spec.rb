# frozen_string_literal: true

require "spec_helper"
require "rake"
require "tmpdir"

# fontisan#156 card 2g: the java-platform gem has no `brotli`. WOFF2 is then
# served by the :ffi tier; the :ruby tier fails at setup with a clear error.
# "brotli unavailable" is simulated on MRI by making the probe say so.
RSpec.describe "brotli as an optional dependency" do
  let(:woff2) { Dir[File.expand_path("../fixtures/fonttools/Test*.woff2", __dir__)].min }
  let(:ttf) { Dir[File.expand_path("../fixtures/fonttools/Test*.ttf", __dir__)].min }
  let(:wrapper) { Fontisan::Utilities::BrotliWrapper }

  around do |example|
    saved = ENV.to_h.slice("FONTISAN_ENGINE", "FONTISAN_ENGINE_STRICT")
    example.run
  ensure
    %w[FONTISAN_ENGINE FONTISAN_ENGINE_STRICT].each { |k| ENV.delete(k) }
    ENV.update(saved)
    Fontisan::Engine.reset!
  end

  def engine(selection, strict: false)
    ENV["FONTISAN_ENGINE"] = selection
    ENV["FONTISAN_ENGINE_STRICT"] = strict ? "1" : nil
    Fontisan::Engine.reset!
  end

  it "has fixtures to run against" do
    expect([woff2, ttf]).to all(be_a(String))
  end

  context "when brotli is unavailable" do
    before { allow(wrapper).to receive(:available?).and_return(false) }

    it "makes the wrapper raise Unavailable, not LoadError, with the remedy" do
      expect { wrapper.compress("x") }
        .to raise_error(wrapper::Unavailable, /brotli.*FONTISAN_ENGINE=ffi/m)
      expect { wrapper.decompress("x") }.to raise_error(wrapper::Unavailable)
    end

    it "fails a WOFF2 read on the :ruby tier at setup, before any parsing" do
      engine("ruby")
      expect { Fontisan::Reference.read(woff2) }
        .to raise_error(Fontisan::Engine::Woff2Unavailable, /read on WOFF2 needs the ffi tier or the `brotli` gem/)
    end

    it "fails a convert to woff2 on the :ruby tier at setup" do
      engine("ruby")
      expect { Fontisan::Reference.convert(ttf, to: :woff2, output: File.join(Dir.tmpdir, "x.woff2")) }
        .to raise_error(Fontisan::Engine::Woff2Unavailable)
    end

    it "leaves non-WOFF2 operations on the :ruby tier alone" do
      engine("ruby")
      expect(Fontisan::Reference.read(ttf)).not_to be_empty
      expect(Fontisan::Engine.served_by(:read)).to eq(:ruby)
    end

    it "routes a WOFF2 read to :ffi when that tier is forced and available" do
      engine("ffi")
      skip "cdylib not built (rake cdylib:build)" unless Fontisan::Ffi.available?
      allow(Fontisan::Native).to receive(:available?).and_return(false)

      expect(Fontisan::Reference.read(woff2)).not_to be_empty
      expect(Fontisan::Engine.served_by(:read)).to eq(:ffi)
    end
  end

  context "when brotli is available" do
    it "does not interfere with a WOFF2 read on the :ruby tier" do
      engine("ruby")
      expect(Fontisan::Reference.read(woff2)).not_to be_empty
      expect(Fontisan::Engine.served_by(:read)).to eq(:ruby)
    end
  end

  describe Fontisan::FfiPlatform do
    it "names a directory per bundled platform" do
      expect(described_class.dir("linux-gnu", "x86_64")).to eq("linux-x86_64")
      expect(described_class.dir("darwin24", "arm64")).to eq("darwin-arm64")
      expect(described_class.dir("darwin24", "x86_64")).to eq("darwin-x86_64")
      expect(described_class.dir("mingw32", "x86_64")).to eq("windows-x86_64")
      expect(described_class.dir("linux", "amd64")).to eq("linux-x86_64") # JRuby
    end

    it "has nothing for a platform the java gem does not bundle" do
      expect(described_class.dir("freebsd14", "x86_64")).to be_nil
    end
  end

  describe "the java gem specification (rake java:gem)" do
    let(:spec) do
      Rake.application.rake_require("java", [File.expand_path("../../rakelib", __dir__)])
      Dir.chdir(File.expand_path("../..", __dir__)) { FontisanJavaGem.spec }
    end

    it "is a java-platform gem with no brotli, rb_sys or extension" do
      expect(spec.platform.to_s).to eq("java")
      names = spec.runtime_dependencies.map(&:name)
      expect(names).not_to include("brotli", "rb_sys")
      expect(names).to include("ffi", "bindata", "nokogiri")
      expect(spec.extensions).to be_empty
      expect(spec.files.grep(%r{\Aext/})).to be_empty
    end

    it "leaves the source gemspec on brotli" do
      Dir.chdir(File.expand_path("../..", __dir__)) { spec } # build the java spec first
      source = Dir.chdir(File.expand_path("../..", __dir__)) { Gem::Specification.load("fontisan.gemspec") }
      expect(source.runtime_dependencies.map(&:name)).to include("brotli")
      expect(source.platform.to_s).to eq("ruby")
    end
  end
end
