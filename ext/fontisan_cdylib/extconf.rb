# frozen_string_literal: true

# Builds the :ffi tier's shared library with cargo and installs it next to
# lib/fontisan/ffi.rb. With no cargo, or FONTISAN_SKIP_CDYLIB=1, it writes a
# Makefile that does nothing, so the gem installs and the :ruby tier serves.
require "mkmf"
require "rbconfig"

here = __dir__
dest = File.expand_path("../../lib/fontisan/ffi", here)
cargo = ENV["FONTISAN_SKIP_CDYLIB"] == "1" ? nil : find_executable("cargo")
extension = case RbConfig::CONFIG["host_os"]
            when /darwin/ then "dylib"
            when /mswin|mingw|cygwin/ then "dll"
            else "so"
            end
prefix = extension == "dll" ? "" : "lib"
built = "target/release/#{prefix}fontisan_cdylib.#{extension}"

makefile =
  if cargo
    <<~MAKE
      all:
      \tcd "#{here}" && "#{cargo}" build --release
      \tmkdir -p "#{dest}"
      \tcp "#{File.join(here, built)}" "#{dest}/"
      install:
      \t@true
      clean:
      \t@true
    MAKE
  else
    warn "fontisan: cargo not found; skipping the :ffi cdylib (the :ruby tier serves)"
    "all:\n\t@true\ninstall:\n\t@true\nclean:\n\t@true\n"
  end
File.write("Makefile", makefile)
