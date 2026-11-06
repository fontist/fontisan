# frozen_string_literal: true

# The :ffi tier's shared library (fontisan#156 card 2d).
namespace :cdylib do
  desc "Build ext/fontisan_cdylib with cargo and install it under lib/fontisan/ffi/"
  task :build do
    require "rbconfig"
    require "fileutils"
    ext = File.expand_path("../ext/fontisan_cdylib", __dir__)
    sh "cargo", "build", "--release", "--manifest-path", File.join(ext, "Cargo.toml")
    suffix = RbConfig::CONFIG["SOEXT"]
    prefix = suffix == "dll" ? "" : "lib"
    dest = File.expand_path("../lib/fontisan/ffi", __dir__)
    FileUtils.mkdir_p(dest)
    FileUtils.cp(File.join(ext, "target/release/#{prefix}fontisan_cdylib.#{suffix}"), dest)
  end

  desc "List the fontisan_* symbols the built library exports (nm -gU / dumpbin); fails if any is missing"
  task :exports do
    lib = Dir[File.expand_path("../lib/fontisan/ffi/*fontisan_cdylib.*", __dir__)].first
    abort "no built library under lib/fontisan/ffi (rake cdylib:build)" unless lib
    listing = if Gem.win_platform? then `dumpbin /exports "#{lib}"` else `nm -gU "#{lib}"` end
    missing = %w[fontisan_abi_version fontisan_call fontisan_result_free].reject { |s| listing.include?(s) }
    abort "missing exports: #{missing.join(', ')}" unless missing.empty?
    puts listing.lines.grep(/fontisan_/)
  end
end
