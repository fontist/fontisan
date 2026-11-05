# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "sfnt"

# Shared helpers for corpus/derive/*.rb. Inputs are resolved through the
# manifest, so a derive script names fonts by id.
module CorpusDerive
  ROOT = File.expand_path("../..", __dir__)

  module_function

  def manifest
    @manifest ||= JSON.parse(File.read(File.join(ROOT, "corpus", "manifest.json")))
  end

  def entry(id)
    manifest.fetch("fonts").find { |f| f["id"] == id } or raise "no manifest entry #{id}"
  end

  # Fetched source font (run `rake corpus:fetch` first).
  def source_bytes(id)
    e = entry(id)
    path = File.join(ROOT, "corpus", "fonts", id, e.fetch("file"))
    raise "#{path} missing: run `rake corpus:fetch`" unless File.exist?(path)

    File.binread(path)
  end

  # Output directory: corpus/derived, or the directory given as ARGV[0]
  # (used to prove the scripts are deterministic).
  def out_dir
    dir = ARGV[0] || File.join(ROOT, "corpus", "derived")
    FileUtils.mkdir_p(dir)
    dir
  end

  def write(name, bytes)
    File.binwrite(File.join(out_dir, name), bytes)
    puts "#{name} #{bytes.bytesize} bytes"
  end
end
