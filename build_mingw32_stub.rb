# frozen_string_literal: true

require "rubygems/package"

# Builds the lib-only x64-mingw32 platform stub (the parsanol-ruby
# release protocol). The newest x64-mingw32 Ruby is 3.0, outside the
# cross-gem ABI set (3.2+), so a native gem cannot exist for that
# platform; the stub carries the pure-Ruby engine so the platform
# matrix on RubyGems is complete for resolvers and installs build
# nothing.
spec = Gem::Specification.load("fontisan.gemspec")
spec.platform = Gem::Platform.new("x64-mingw32")
spec.extensions = []
spec.files = spec.files.reject { |f| f.start_with?("ext/") }
Gem::Package.build(spec)
