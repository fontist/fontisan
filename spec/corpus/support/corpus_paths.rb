# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../../../lib", __dir__))
require "fontisan"
require "json"

# Path lookup for corpus specs. They run without spec_helper (which downloads
# ~400 MB of fixtures): `bundle exec rspec --options /dev/null spec/corpus/...`
# after `bundle exec rake corpus:fetch`.
module CorpusPaths
  ROOT = File.expand_path("../../..", __dir__)

  module_function

  def manifest
    @manifest ||= JSON.parse(File.read(File.join(ROOT, "corpus", "manifest.json")))
  end

  def entry(id)
    manifest.fetch("fonts").find { |f| f["id"] == id } or raise KeyError, id
  end

  def path(id)
    e = entry(id)
    dir = e["type"] == "derived" ? "derived" : File.join("fonts", e["id"])
    File.join(ROOT, "corpus", dir, e["file"])
  end
end
