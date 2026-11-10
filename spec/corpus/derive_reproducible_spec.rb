# frozen_string_literal: true

require_relative "support/corpus_paths"
require "open3"
require "tmpdir"
require "rbconfig"

# `rake corpus:derive` must leave the committed corpus/derived untouched. Each
# derive script is run into a scratch directory (the scripts take it as ARGV[0])
# and its output is compared BYTE-FOR-BYTE with the committed file. The WOFF2
# collection used to differ on every run because the encoder stamped the clock
# into head.modified; the script now pins it.
#
# Needs the fetched sources: `bundle exec rake corpus:fetch`.
RSpec.describe "corpus:derive reproducibility" do
  scripts = %w[quirks malformed malformed_woff fuzz ttc_multi woff2_collection]
  let(:derived_dir) { File.join(CorpusPaths::ROOT, "corpus", "derived") }

  scripts.each do |name|
    it "#{name}.rb reproduces its committed files byte-for-byte" do
      Dir.mktmpdir("corpus-derive") do |out|
        script = File.join(CorpusPaths::ROOT, "corpus", "derive", "#{name}.rb")
        _, err, status = Open3.capture3(RbConfig.ruby, script, out, chdir: CorpusPaths::ROOT)
        expect(status).to be_success, err

        produced = Dir.children(out).sort
        expect(produced).not_to be_empty
        produced.each do |file|
          expect(File.binread(File.join(out, file))).to eq(File.binread(File.join(derived_dir, file))),
                                                        "#{file} differs from the committed copy"
        end
      end
    end
  end
end
