# frozen_string_literal: true

# The `java`-platform gem (fontisan#156 card 2g). `brotli` is a C extension with
# no JRuby build, and a gemspec is evaluated when the gem is built, so JRuby
# gets its own gem: no `brotli`, no `rb_sys`, no magnus extension, a runtime
# dependency on `ffi`, and the cdylib for every bundled OS and architecture
# under lib/fontisan/ffi/<platform>/ (see Fontisan::FfiPlatform). WOFF2 there is
# served by the :ffi tier.
#
#   rake java:gem                      # builds the host's cdylib, packs what is staged
#   FONTISAN_JAVA_ALL=1 rake java:gem  # CI: the four are already staged (extracted
#                                      # from the platform gems); fail unless all are
#   rake java:stage                    # only copies the host's cdylib into its directory
require "fileutils"
require "rubygems/package"
require_relative "../lib/fontisan/ffi_platform"

# Builds the java gem's specification from fontisan.gemspec.
module FontisanJavaGem
  STAGED = "lib/fontisan/ffi/*/*fontisan_cdylib.{so,dylib,dll}"

  def self.spec
    # load caches its result: copy, or the mutations below reach the source spec.
    base = Gem::Specification.load("fontisan.gemspec").dup
    base.platform = "java"
    base.extensions = []
    base.dependencies.delete_if { |d| %w[brotli rb_sys].include?(d.name) }
    base.add_dependency "ffi", "~> 1.15"
    base.files = base.files.reject { |f| f.start_with?("ext/") } + Dir[STAGED]
    base
  end

  def self.staged_platforms
    Dir[STAGED].map { |f| File.basename(File.dirname(f)) }.uniq
  end
end

namespace :java do
  desc "Build the host cdylib and copy it to lib/fontisan/ffi/<platform>/"
  task :stage do
    next if ENV["FONTISAN_JAVA_ALL"]

    dir = Fontisan::FfiPlatform.dir or abort "no java-gem directory for #{RbConfig::CONFIG['host_os']}"
    Rake::Task["cdylib:vendor"].invoke
    dest = File.join("lib/fontisan/ffi", dir)
    FileUtils.mkdir_p(dest)
    FileUtils.cp(Dir["lib/fontisan/ffi/*fontisan_cdylib.{so,dylib,dll}"], dest)
  end

  desc "Build pkg/fontisan-VERSION-java.gem without brotli, bundling the staged cdylibs"
  task gem: :stage do
    missing = Fontisan::FfiPlatform::DIRS - FontisanJavaGem.staged_platforms
    abort "missing cdylibs for: #{missing.join(', ')}" if ENV["FONTISAN_JAVA_ALL"] && !missing.empty?
    puts "bundling cdylibs for: #{FontisanJavaGem.staged_platforms.join(', ')}; not staged: #{missing.join(', ')}"

    FileUtils.mkdir_p("pkg")
    built = Gem::Package.build(FontisanJavaGem.spec)
    FileUtils.mv(built, "pkg/")
    puts "pkg/#{built}"
  end
end
