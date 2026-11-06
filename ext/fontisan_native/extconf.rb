# frozen_string_literal: true

# Builds the :native tier. Degrades cleanly: without a Rust toolchain (or the
# rb_sys gem) it writes a no-op Makefile, the gem installs without the
# extension, and Fontisan::Native.available? is false, so only the :ruby tier
# serves. Set FONTISAN_NATIVE_REQUIRED=1 to turn that degradation into a failure.
require "mkmf"

def cargo_present?
  system("cargo", "--version", out: File::NULL, err: File::NULL)
rescue SystemCallError
  false
end

def skip_native(reason)
  abort "fontisan: cannot build the native extension: #{reason}" if ENV["FONTISAN_NATIVE_REQUIRED"] == "1"

  warn "fontisan: skipping the native extension (#{reason}); the :ruby engine tier serves."
  File.write("Makefile", <<~MAKEFILE)
    all:
    install:
    clean:
    distclean:
    .PHONY: all install clean distclean
  MAKEFILE
end

if cargo_present?
  begin
    require "rb_sys/mkmf"
    create_rust_makefile("fontisan/native/fontisan_native")
  rescue LoadError
    skip_native("the rb_sys gem is not installed")
  end
else
  skip_native("cargo not found")
end
