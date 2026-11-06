# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "stringio"

# Card 2f-cli: `fontisan convert` and `fontisan unpack`, entered through the
# Thor CLI, go through the engine selection. Needs the built extension
# (`bundle exec rake compile`) and library (`rake cdylib:build`); a missing
# tier fails the examples, it never skips them.
RSpec.describe "CLI through the engine tiers" do
  let(:fixtures) { File.expand_path("../fixtures", __dir__) }
  let(:ttf) { File.join(fixtures, "fonttools", "TestTTF.ttf") }
  let(:ttc) { File.join(fixtures, "fonttools", "TestTTC.ttc") }
  let(:vf) { File.join(fixtures, "fonts", "MonaSansVF", "MonaSansMonoVF[wght].ttf") }
  let(:stamp) { Time.at(1_735_689_600) }

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

  def cli(*args)
    out = StringIO.new
    saved = $stdout
    $stdout = out
    allow(Time).to receive(:now).and_return(stamp)
    Fontisan::Cli.start(args)
    out.string
  ensure
    $stdout = saved
  end

  # Decoded tables of a font, read by the Ruby tier whatever produced it. The
  # compressed file's own hash is the one thing that may differ (zlib/brotli
  # build), so it is the only field dropped.
  def decoded(path)
    with_engine("ruby", strict: false) do
      Fontisan::Reference.read(path, mode: :full).map { |face| face.except("file_sha256") }
    end
  end

  def tree(dir)
    Dir.children(dir).sort.to_h { |name| [name, File.binread(File.join(dir, name))] }
  end

  %w[native ffi].each do |name|
    describe "the #{name} tier (strict)" do
      def tier(selection, &) = with_engine(selection, &)

      %w[ttf otf woff woff2].each do |target|
        it "serves `convert --to #{target}` and writes what Ruby writes" do
          Dir.mktmpdir do |dir|
            n = File.join(dir, "n.#{target}")
            r = File.join(dir, "r.#{target}")
            printed = tier(name) do
              cli("convert", ttf, "--to", target, "--output", n).tap do
                expect(Fontisan::Engine.served_by(:convert)).to eq(name.to_sym)
              end
            end
            with_engine("ruby", strict: false) { cli("convert", ttf, "--to", target, "--output", r, "--quiet") }

            if %w[woff woff2].include?(target)
              expect(decoded(n)).to eq(decoded(r))
            else
              expect(File.binread(n)).to eq(File.binread(r))
            end
            expect(printed).to include("Conversion complete!", "Output: #{n}")
          end
        end
      end

      it "serves a collection conversion" do
        Dir.mktmpdir do |dir|
          n = File.join(dir, "n.otc")
          r = File.join(dir, "r.otc")
          tier(name) do
            cli("convert", ttc, "--to", "otc", "--output", n, "--quiet")
            expect(Fontisan::Engine.served_by(:convert)).to eq(name.to_sym)
          end
          with_engine("ruby", strict: false) { cli("convert", ttc, "--to", "otc", "--output", r, "--quiet") }
          expect(File.binread(n)).to eq(File.binread(r))
        end
      end

      it "keeps what the engine cannot serve on Ruby" do
        Dir.mktmpdir do |dir|
          tier(name) do
            cli("convert", vf, "--to", "ttf", "--output", File.join(dir, "a.ttf"), "--wght", "700", "--quiet")
            expect(Fontisan::Engine.served_by(:convert)).to be_nil
            cli("convert", ttf, "--to", "woff", "woff2", "--output", File.join(dir, "multi"), "--quiet")
            expect(Fontisan::Engine.served_by(:convert)).to be_nil
            cli("convert", ttf, "--to", "otf", "--output", File.join(dir, "h.otf"), "--preserve-hints", "--quiet")
            expect(Fontisan::Engine.served_by(:convert)).to be_nil
          end
        end
      end

      it "serves `unpack` of every member and writes the files Ruby writes" do
        Dir.mktmpdir do |dir|
          n = File.join(dir, "n")
          r = File.join(dir, "r")
          printed = tier(name) do
            cli("unpack", ttc, "--output-dir", n).tap do
              expect(Fontisan::Engine.served_by(:extract)).to eq(name.to_sym)
            end
          end
          with_engine("ruby", strict: false) { cli("unpack", ttc, "--output-dir", r, "--quiet") }

          expect(tree(n).keys).to eq(tree(r).keys)
          expect(tree(n)).to eq(tree(r))
          expect(printed).to include("Collection unpacked successfully:", "Fonts extracted: #{tree(n).size}/#{tree(n).size}")
        end
      end

      it "serves `unpack --font-index` of one member and writes the file Ruby writes" do
        Dir.mktmpdir do |dir|
          n = File.join(dir, "n")
          r = File.join(dir, "r")
          tier(name) do
            cli("unpack", ttc, "--output-dir", n, "--font-index", "1", "--quiet")
            expect(Fontisan::Engine.served_by(:extract)).to eq(name.to_sym)
          end
          with_engine("ruby", strict: false) { cli("unpack", ttc, "--output-dir", r, "--font-index", "1", "--quiet") }
          expect(tree(n).size).to eq(1)
          expect(tree(n)).to eq(tree(r))
        end
      end

      it "keeps `unpack --format`, --prefix and an out-of-range index on Ruby" do
        Dir.mktmpdir do |dir|
          tier(name) do
            cli("unpack", ttc, "--output-dir", File.join(dir, "f"), "--format", "woff", "--quiet")
            expect(Fontisan::Engine.served_by(:extract)).to be_nil
            cli("unpack", ttc, "--output-dir", File.join(dir, "p"), "--prefix", "X", "--quiet")
            expect(Fontisan::Engine.served_by(:extract)).to be_nil
            expect { cli("unpack", ttc, "--output-dir", File.join(dir, "o"), "--font-index", "99", "--quiet") }
              .to raise_error(ArgumentError, /out of range/)
            expect(Fontisan::Engine.served_by(:extract)).to be_nil
          end
        end
      end
    end
  end
end
