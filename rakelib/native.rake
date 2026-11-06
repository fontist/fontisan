# frozen_string_literal: true

# Builds the :native tier (ext/fontisan_native, magnus + rb-sys) into
# lib/fontisan/native/ with `rake compile`. Needs a Rust toolchain: without
# cargo (or the rb_sys gem) the task is not defined and every other task
# still loads.
cargo = begin
  system("cargo", "--version", out: File::NULL, err: File::NULL)
rescue SystemCallError
  false
end

if cargo
  begin
    require "rb_sys/extensiontask"

    RbSys::ExtensionTask.new("fontisan_native", Gem::Specification.load("fontisan.gemspec")) do |ext|
      ext.ext_dir = "ext/fontisan_native"
      ext.lib_dir = "lib/fontisan/native"
    end
  rescue LoadError
    # rb_sys / rake-compiler absent: nothing to compile.
  end
end
