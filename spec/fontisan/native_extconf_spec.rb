# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

# Runs ext/fontisan_native/extconf.rb, then `make` and `make install`, in a
# scratch directory with stub cargo/rustc and a stubbed rb_sys. One stub's
# generated Makefile always fails to build, mimicking the Windows "Cargo target
# does not match Ruby" failure that broke `gem install` from source; the other
# raises while configuring, as rb_sys does for a target mismatch or a missing
# rustc before any mkmf check.
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

  def require_make!
    skip "needs a POSIX shell and make" if Gem.win_platform? || !make_cmd
  end

  def run_in(dir, env, *cmd)
    Open3.capture2e({ "PATH" => "#{File.join(dir, 'bin')}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}" }.merge(env),
                    *cmd, chdir: File.join(dir, "build"))
  end

  # A succeeding `<name> --version` on PATH: a .bat on Windows, a sh script elsewhere.
  def stub_tool(name)
    return File.write(File.join(dir, "bin", "#{name}.bat"), "@exit /b 0\r\n") if Gem.win_platform?

    File.write(File.join(dir, "bin", name), "#!/bin/sh\nexit 0\n")
    FileUtils.chmod(0o755, File.join(dir, "bin", name))
  end

  def native_binaries
    Dir.glob(File.join(dir, "build", "**", "fontisan_native.*")).reject { |f| File.directory?(f) }
  end

  before do
    FileUtils.mkdir_p([File.join(dir, "bin"), File.join(dir, "build"), File.join(dir, "stub", "rb_sys")])
    %w[cargo rustc].each { |tool| stub_tool(tool) }
    File.write(File.join(dir, "stub", "rb_sys", "mkmf.rb"), stub_rb_sys)
  end

  after { FileUtils.remove_entry(dir) }

  def configure(env = {})
    run_in(dir, env, RbConfig.ruby, "-I#{File.join(dir, 'stub')}", extconf)
  end

  it "installs without the extension when the native build fails" do
    require_make!
    _, status = configure
    expect(status).to be_success

    out, status = run_in(dir, {}, make_cmd)
    expect(status).to be_success
    expect(out).to include("the :ruby engine tier serves")

    out, status = run_in(dir, {}, make_cmd, "install")
    expect(status).to be_success
    expect(out).to include("the :ruby engine tier serves")
    expect(native_binaries).to be_empty
  end

  it "also survives make clean failing" do
    require_make!
    configure
    _, status = run_in(dir, {}, make_cmd, "clean")
    expect(status).to be_success
  end

  it "fails the build when FONTISAN_NATIVE_REQUIRED=1" do
    require_make!
    env = { "FONTISAN_NATIVE_REQUIRED" => "1" }
    _, status = configure(env)
    expect(status).to be_success

    out, status = run_in(dir, env, make_cmd)
    expect(status).not_to be_success
    expect(out).to include("cargo build failed")
  end

  context "when rb_sys raises while configuring" do
    let(:stub_rb_sys) do
      <<~'RUBY'
        def create_rust_makefile(_name)
          File.write("Makefile", "all:\n\t@exit 1\n")
          raise "Cargo target x86_64-pc-windows-gnu does not match Ruby x64-mingw-ucrt"
        end
      RUBY
    end

    it "writes the no-op Makefile and warns that the :ruby tier serves" do
      out, status = configure
      expect(status).to be_success
      expect(out).to include("does not match Ruby", "the :ruby engine tier serves")
      expect(File.read(File.join(dir, "build", "Makefile"))).to start_with("all:\ninstall:\n")
      expect(File).not_to exist(File.join(dir, "build", "Makefile.rb_sys"))

      require_make!
      [[make_cmd], [make_cmd, "install"]].each do |cmd|
        _, status = run_in(dir, {}, *cmd)
        expect(status).to be_success
      end
      expect(native_binaries).to be_empty
    end

    it "fails extconf when FONTISAN_NATIVE_REQUIRED=1" do
      out, status = configure("FONTISAN_NATIVE_REQUIRED" => "1")
      expect(status).not_to be_success
      expect(out).to include("cannot build the native extension", "does not match Ruby")
    end
  end
end
