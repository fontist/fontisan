# frozen_string_literal: true

# The :ffi tier's shared library (fontisan#156 card 2d).
namespace :cdylib do
  desc "Build ext/fontisan_cdylib with cargo and install it under lib/fontisan/ffi/"
  task build: :vendor

  desc "Build the cdylib for the active cross target (CARGO_BUILD_TARGET / RUST_TARGET) and vendor it into lib/fontisan/ffi/"
  task :vendor do
    require "rbconfig"
    require "fileutils"
    ext = File.expand_path("../ext/fontisan_cdylib", __dir__)
    triple = ENV["CARGO_BUILD_TARGET"] || ENV.fetch("RUST_TARGET", nil)
    if triple.nil? && ENV.key?("RUBY_TARGET") # a cross build outside rb-sys-dock
      require "rb_sys/toolchain_info"
      triple = RbSys::ToolchainInfo.new(ENV.fetch("RUBY_TARGET")).rust_target
    end
    args = ["cargo", "build", "--release", "--locked", "--manifest-path", File.join(ext, "Cargo.toml")]
    args += ["--target", triple] if triple
    sh(*args)
    release = File.join(ENV.fetch("CARGO_TARGET_DIR", File.join(ext, "target")), triple.to_s, "release")
    built = Dir[File.join(release, "{lib,}fontisan_cdylib.{so,dylib,dll}")].first
    abort "cdylib not found under #{release}" unless built

    dest = File.expand_path("../lib/fontisan/ffi", __dir__)
    FileUtils.mkdir_p(dest)
    FileUtils.cp(built, dest)
  end

  desc "List the fontisan_* symbols the built library exports (nm -gU / dumpbin); fails if any is missing"
  task :exports do
    lib = Dir[File.expand_path("../lib/fontisan/ffi/*fontisan_cdylib.*", __dir__)].first
    abort "no built library under lib/fontisan/ffi (rake cdylib:build)" unless lib
    listing = if Gem.win_platform? then `dumpbin /exports "#{lib}"` else `nm -gU "#{lib}"` end
    missing = %w[fontisan_abi_version fontisan_call fontisan_result_free fontisan_cdylib_engine_rev].reject { |s| listing.include?(s) }
    abort "missing exports: #{missing.join(', ')}" unless missing.empty?
    puts listing.lines.grep(/fontisan_/)
  end
end
