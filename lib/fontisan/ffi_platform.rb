# frozen_string_literal: true

module Fontisan
  # Names the per-platform directory under lib/fontisan/ffi/ that holds a
  # cdylib in the `java`-platform gem. That gem is one artefact for every OS,
  # so the library cannot sit at one flat path the way it does in a platform
  # gem (two macOS architectures would collide). Shared by {Fontisan::Ffi}
  # and rakelib/java.rake.
  module FfiPlatform
    DIRS = %w[linux-x86_64 darwin-arm64 darwin-x86_64 windows-x86_64].freeze

    # @return [String, nil] one of {DIRS}, nil for an unbundled platform
    def self.dir(host_os = RbConfig::CONFIG["host_os"], host_cpu = RbConfig::CONFIG["host_cpu"])
      os = case host_os
           when /darwin/ then "darwin"
           when /mswin|mingw|cygwin|windows/ then "windows"
           when /linux/ then "linux"
           end
      cpu = host_cpu.to_s.match?(/arm64|aarch64/) ? "arm64" : "x86_64"
      candidate = "#{os}-#{cpu}"
      DIRS.include?(candidate) ? candidate : nil
    end
  end
end
