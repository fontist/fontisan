# frozen_string_literal: true

# Builds the :native tier. Degrades cleanly: without a Rust toolchain (or the
# rb_sys gem) it writes a no-op Makefile, the gem installs without the
# extension, and Fontisan::Native.available? is false, so only the :ruby tier
# serves. Set FONTISAN_NATIVE_REQUIRED=1 to turn that degradation into a failure.
#
# A failure at `make` time (a Cargo/Ruby target mismatch on Windows, a missing
# linker, an old rustc) degrades the same way: rb_sys's Makefile is kept as
# Makefile.rb_sys and a wrapper Makefile runs it, turning its failure into a
# warning. Only POSIX-sh-compatible recipe syntax is used (`cmd || echo`), so it
# works under GNU make on Linux/macOS and the RubyInstaller devkit (msys sh).
require "mkmf"

RB_SYS_MAKEFILE = "Makefile.rb_sys"

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

# Wraps the rb_sys Makefile so that a failing build/install/clean leaves the gem
# installed without the extension (unless FONTISAN_NATIVE_REQUIRED=1).
def wrap_rust_makefile
  return if ENV["FONTISAN_NATIVE_REQUIRED"] == "1"

  File.rename("Makefile", RB_SYS_MAKEFILE)
  warning = %(echo "fontisan: the native extension did not build; the :ruby engine tier serves.")
  targets = %w[all install clean distclean].map do |target|
    "#{target}:\n\t$(MAKE) -f #{RB_SYS_MAKEFILE} #{target} || #{warning}\n"
  end
  File.write("Makefile", "#{targets.join}\n.PHONY: all install clean distclean\n")
end

if cargo_present?
  begin
    require "rb_sys/mkmf"
    create_rust_makefile("fontisan/native/fontisan_native")
    wrap_rust_makefile
  rescue LoadError
    skip_native("the rb_sys gem is not installed")
  end
else
  skip_native("cargo not found")
end
