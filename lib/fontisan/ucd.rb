# frozen_string_literal: true

# Namespace file for UCD (Unicode Character Database) support.
#
# All Ucd::* constants are autoloaded from here. Top-level callers
# (`lib/fontisan.rb`) require this file; downstream files reference
# constants like Ucd::CacheManager and let autoload do the work.

module Fontisan
  module Ucd
    autoload :Config,              "fontisan/ucd/config"
    autoload :CacheManager,        "fontisan/ucd/cache_manager"
    autoload :Downloader,          "fontisan/ucd/downloader"
    autoload :VersionResolver,     "fontisan/ucd/version_resolver"
    autoload :IndexBuilder,        "fontisan/ucd/index_builder"
    autoload :Index,               "fontisan/ucd/index"
    autoload :Aggregator,          "fontisan/ucd/aggregator"
    autoload :RangeEntry,          "fontisan/ucd/range_entry"
    autoload :Error,               "fontisan/ucd/error"
    autoload :DownloadError,       "fontisan/ucd/download_error"
    autoload :UnknownVersionError, "fontisan/ucd/unknown_version_error"
  end
end
