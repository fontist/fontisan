# frozen_string_literal: true

# Namespace hub for CLDR (Common Locale Data Repository) support.
#
# Provides per-language exemplar character sets so the audit can
# compute "this font covers X% of language Y". All Cldr::* constants
# are autoloaded from here.

module Fontisan
  module Cldr
    autoload :Config,              "fontisan/cldr/config"
    autoload :CacheManager,        "fontisan/cldr/cache_manager"
    autoload :Downloader,          "fontisan/cldr/downloader"
    autoload :VersionResolver,     "fontisan/cldr/version_resolver"
    autoload :IndexBuilder,        "fontisan/cldr/index_builder"
    autoload :Index,               "fontisan/cldr/index"
    autoload :Aggregator,          "fontisan/cldr/aggregator"
    autoload :UnicodeSetParser,    "fontisan/cldr/unicode_set_parser"
    autoload :Error,               "fontisan/cldr/error"
    autoload :DownloadError,       "fontisan/cldr/download_error"
    autoload :UnknownVersionError, "fontisan/cldr/unknown_version_error"
  end
end
