# frozen_string_literal: true

# Builds the :native tier (ext/fontisan_native, magnus + rb-sys) into
# lib/fontisan/native/ with `rake compile`, and the platform gems with
# `rake native gem` (this machine) or rb-sys-dock / oxidize-rb/actions/cross-gem
# (see .github/workflows/gem-build.yml). Needs a Rust toolchain: without cargo
# (or the rb_sys gem) the task is not defined and every other task still loads.
cargo = begin
  system("cargo", "--version", out: File::NULL, err: File::NULL)
rescue SystemCallError
  false
end

# A musl cdylib cannot link with a static C runtime, and the native extension
# is itself a shared object. rb-sys-dock exports the target as RUST_TARGET.
rust_target = ENV["CARGO_BUILD_TARGET"] || ENV["RUST_TARGET"] || ENV.fetch("RUBY_TARGET", nil)
if rust_target.to_s.include?("musl") && !ENV.fetch("RUSTFLAGS", "").include?("crt-static")
  ENV["RUSTFLAGS"] = [ENV.fetch("RUSTFLAGS", nil), "-C target-feature=-crt-static"].compact.join(" ")
end

if cargo
  begin
    require "rb_sys/extensiontask"

    RbSys::ExtensionTask.new("fontisan_native", Gem::Specification.load("fontisan.gemspec")) do |ext|
      ext.ext_dir = "ext/fontisan_native"
      ext.lib_dir = "lib/fontisan/native"

      # Runs when a platform gem's spec is assembled. The platform gem carries
      # its binaries and builds nothing at install: no extension, no rb_sys, no
      # cdylib sources, and the cdylib built for this target (lib/fontisan/ffi)
      # next to the magnus extension, so the :ffi tier works too.
      ext.cross_compiling do |spec|
        Rake::Task["cdylib:vendor"].invoke
        spec.extensions.clear
        spec.files.reject! { |f| f.start_with?("ext/") }
        spec.files += Dir["lib/fontisan/ffi/*.{so,dylib,dll}"]
      end
    end
  rescue LoadError
    # rb_sys / rake-compiler absent: nothing to compile.
  end
end
