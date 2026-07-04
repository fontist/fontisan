# frozen_string_literal: true

module Fontisan
  # Tasks supporting the developer workflow: fixture downloads, etc.
  # Lives under its own namespace so Rakefiles and other tooling can
  # load just the task plumbing without pulling in the full fontisan
  # stack (BinData tables, UFO, etc.).
  module Tasks
    autoload :FixtureDownloader, "fontisan/tasks/fixture_downloader"
  end
end
