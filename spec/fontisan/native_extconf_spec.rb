# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

# Runs ext/fontisan_native/extconf.rb, then `make` and `make install`, in a
# scratch directory with a stubbed rb_sys whose generated Makefile always
# fails to build, mimicking the Windows "Cargo target does not match Ruby"
# failure that broke `gem install` from source.
RSpec.describe "ext/fontisan_native/extconf.rb build fallback" do
  let(:extconf) { File.expand_path("../../ext/fontisan_native/extconf.rb", __dir__) }
  let(:dir) { Dir.mktmpdir("fontisan-extconf") }
  let(:stub_rb_sys) do
    <<~'RUBY'
      def create_rust_makefile(_name)
        File.write("Makefile", "all:\n\t@echo cargo build failed >&2\n\t@exit 1\n" \
                               "install:\n\t@echo cargo build failed >&2\n\t@exit 1\n" \
                               "clean:\n\t@exit 1\n")
      end
    RUBY
  end

  def make_cmd
    %w[gmake make].find { |m| system(m, "--version", out: File::NULL, err: File::NULL) }
  end

  def run_in(dir, env, *cmd)
    Open3.capture2e({ "PATH" => "#{File.join(dir, 'bin')}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}" }.merge(env),
                    *cmd, chdir: File.join(dir, "build"))
  end

  before do
    skip "needs a POSIX shell and make" if Gem.win_platform? || !make_cmd

    FileUtils.mkdir_p([File.join(dir, "bin"), File.join(dir, "build"), File.join(dir, "stub", "rb_sys")])
    File.write(File.join(dir, "bin", "cargo"), "#!/bin/sh\nexit 0\n")
    FileUtils.chmod(0o755, File.join(dir, "bin", "cargo"))
    File.write(File.join(dir, "stub", "rb_sys", "mkmf.rb"), stub_rb_sys)
  end

  after { FileUtils.remove_entry(dir) }

  def configure(env = {})
    run_in(dir, env, RbConfig.ruby, "-I#{File.join(dir, 'stub')}", extconf)
  end

  it "installs without the extension when the native build fails" do
    _, status = configure
    expect(status).to be_success

    out, status = run_in(dir, {}, make_cmd)
    expect(status).to be_success
    expect(out).to include("the :ruby engine tier serves")

    out, status = run_in(dir, {}, make_cmd, "install")
    expect(status).to be_success
    expect(out).to include("the :ruby engine tier serves")
    expect(Dir.glob(File.join(dir, "build", "**", "fontisan_native.*")).reject { |f| File.directory?(f) }).to be_empty
  end

  it "also survives make clean failing" do
    configure
    _, status = run_in(dir, {}, make_cmd, "clean")
    expect(status).to be_success
  end

  it "fails the build when FONTISAN_NATIVE_REQUIRED=1" do
    env = { "FONTISAN_NATIVE_REQUIRED" => "1" }
    _, status = configure(env)
    expect(status).to be_success

    out, status = run_in(dir, env, make_cmd)
    expect(status).not_to be_success
    expect(out).to include("cargo build failed")
  end
end
