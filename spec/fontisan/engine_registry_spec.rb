# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"
require "tmpdir"
require "fileutils"

RSpec.describe Fontisan::Engine do
  let(:tier) do
    Module.new do
      def self.available? = true
      def self.supports?(_operation, _path = nil) = true
      def self.call(*) = [:registered]
    end
  end

  around do |example|
    saved_env = ENV.to_h.slice("FONTISAN_ENGINE", "FONTISAN_ENGINE_STRICT")
    providers = described_class.instance_variable_get(:@registered_tiers)
    described_class.instance_variable_set(:@registered_tiers, {}.freeze)
    described_class.reset!
    ENV["FONTISAN_ENGINE"] = "native"
    ENV["FONTISAN_ENGINE_STRICT"] = "1"
    example.run
  ensure
    ENV.delete("FONTISAN_ENGINE")
    ENV.delete("FONTISAN_ENGINE_STRICT")
    ENV.update(saved_env)
    described_class.instance_variable_set(:@registered_tiers, providers)
    described_class.reset!
  end

  describe ".register_tier" do
    it "dispatches to a registered native provider in strict mode" do
      described_class.register_tier(:native, tier)

      expect(Fontisan::Reference.read("registered.ttf")).to eq([:registered])
      expect(described_class.served_by(:read)).to eq(:native)
    end

    it "accepts the ffi name as a string" do
      described_class.register_tier("ffi", tier)
      ENV["FONTISAN_ENGINE"] = "ffi"

      expect(Fontisan::Reference.read("registered.ttf")).to eq([:registered])
      expect(described_class.served_by(:read)).to eq(:ffi)
    end

    it "rejects replacement of the Ruby tier" do
      expect { described_class.register_tier(:ruby, tier) }
        .to raise_error(described_class::ConfigError, /only native and ffi/)
    end

    it "rejects an unknown tier name" do
      expect { described_class.register_tier(:rust, tier) }
        .to raise_error(described_class::ConfigError, /only native and ffi/)
    end

    it "rejects a provider missing the contract without replacing a valid one" do
      described_class.register_tier(:native, tier)

      expect { described_class.register_tier(:native, Module.new) }
        .to raise_error(described_class::ConfigError, /available\?, supports\?, call/)
      expect(described_class.resolve(:read)).to eq(:native)
    end

    it "invalidates a cached unavailable probe when a provider is registered" do
      expect { described_class.setup! }
        .to raise_error(described_class::TierUnavailable)

      described_class.register_tier(:native, tier)

      expect(described_class.resolve(:read)).to eq(:native)
    end

    it "invalidates a cached available probe when a provider is replaced" do
      described_class.register_tier(:native, tier)
      expect(described_class.resolve(:read)).to eq(:native)
      unavailable = tier.dup
      allow(unavailable).to receive(:available?).and_return(false)
      described_class.register_tier(:native, unavailable)

      expect { described_class.setup! }
        .to raise_error(described_class::TierUnavailable)
    end

    it "retains providers across reset without requiring a reset method" do
      described_class.register_tier(:native, tier)
      described_class.reset!

      expect(Fontisan::Reference.read("registered.ttf")).to eq([:registered])
    end

    it "resets provider probes when a reset method is supplied" do
      allow(tier).to receive(:reset!)
      described_class.register_tier(:native, tier)
      described_class.reset!

      expect(tier).to have_received(:reset!)
    end

    it "restores the provider after resetting a temporary register override" do
      described_class.register_tier(:native, tier)
      override = tier.dup
      allow(override).to receive(:call).and_return([:override])
      described_class.register(:native, override)
      expect(Fontisan::Reference.read("registered.ttf")).to eq([:override])

      described_class.reset!

      expect(Fontisan::Reference.read("registered.ttf")).to eq([:registered])
    end

    it "preserves a registration made before Reference loads" do
      script = <<~RUBY
        require "fontisan"
        tier = Module.new do
          def self.available? = true
          def self.supports?(*) = true
          def self.call(*) = :registered
        end
        Fontisan::Engine.register_tier(:native, tier)
        abort "Reference loaded early" unless Fontisan.autoload?(:Reference)
        print Fontisan::Reference.read("registered.ttf")
      RUBY
      out, err, status = Open3.capture3(
        RbConfig.ruby, "-I#{File.expand_path('../../lib', __dir__)}",
        "-e", script
      )

      expect([status.success?, out]).to eq([true, "registered"]), err
    end
  end

  describe "an unregistered tier" do
    before do
      allow(described_class).to receive(:require)
        .with(described_class::FACE_ENTRY).and_raise(LoadError)
    end

    %w[native ffi].each do |name|
      it "falls back to Ruby for #{name} without strict mode" do
        ENV["FONTISAN_ENGINE"] = name
        ENV["FONTISAN_ENGINE_STRICT"] = "0"

        expect(described_class.resolve(:read)).to eq(:ruby)
        expect(described_class).to have_received(:require)
          .with(described_class::FACE_ENTRY)
      end

      it "raises TierUnavailable for #{name} in strict mode" do
        ENV["FONTISAN_ENGINE"] = name

        expect { described_class.setup! }
          .to raise_error(described_class::TierUnavailable, /#{name}/)
        expect(described_class).to have_received(:require)
          .with(described_class::FACE_ENTRY)
      end
    end
  end

  describe "loading the optional face in a fresh process" do
    let(:face_dir) { File.realpath(Dir.mktmpdir("fontisan-face")) }
    let(:face_file) { File.join(face_dir, "#{described_class::FACE_ENTRY}.rb") }
    let(:script) do
      <<~RUBY
        require "fontisan"
        abort "face loaded eagerly" if $LOADED_FEATURES.include?(#{face_file.inspect})
        #{operation}
      RUBY
    end
    let(:result) do
      Open3.capture3(
        RbConfig.ruby, "-I#{face_dir}",
        "-I#{File.expand_path('../../lib', __dir__)}", "-e", script
      )
    end

    before do
      FileUtils.mkdir_p(File.dirname(face_file))
      File.write(face_file, <<~RUBY)
        module Fontisan::Ruby
          def self.available? = true
          def self.supports?(*) = true
          def self.call(*) = :face
        end
        Fontisan::Engine.register(:native, Fontisan::Ruby)
        Fontisan::Engine.register(:ffi, Fontisan::Ruby)
      RUBY
    end

    after { FileUtils.remove_entry(face_dir) }

    %w[ruby auto].each do |selection|
      context "when #{selection} is selected" do
        let(:operation) do
          <<~RUBY
            ENV["FONTISAN_ENGINE"] = #{selection.inspect}
            print Fontisan::Engine.resolve(:read)
            abort "face loaded for Ruby" if $LOADED_FEATURES.include?(#{face_file.inspect})
          RUBY
        end

        it "keeps the face unloaded" do
          out, err, status = result

          expect([status.success?, out]).to eq([true, "ruby"]), err
        end
      end
    end

    %w[native ffi].each do |selection|
      context "when #{selection} is selected in strict mode" do
        let(:operation) do
          <<~RUBY
            ENV["FONTISAN_ENGINE"] = #{selection.inspect}
            ENV["FONTISAN_ENGINE_STRICT"] = "1"
            Fontisan::Engine.setup!
            abort "face was not loaded" unless $LOADED_FEATURES.include?(#{face_file.inspect})
            print Fontisan::Reference.read("face.ttf")
            Fontisan::Engine.reset!
            print Fontisan::Reference.read("face.ttf")
          RUBY
        end

        it "loads the face and retains its self-registered tiers across resets" do
          out, err, status = result

          expect([status.success?, out]).to eq([true, "faceface"]), err
        end
      end
    end

    context "without the face gem" do
      before { File.delete(face_file) }

      let(:operation) do
        <<~RUBY
          engine = Fontisan::Engine
          # Model the Ruby-only install after the bundled tiers move out.
          engine.instance_variable_set(:@registered_tiers, {}.freeze)
          begin
            print engine.resolve(:read)
          rescue Fontisan::Engine::TierUnavailable
            print "unavailable"
          end
        RUBY
      end

      it "falls back to Ruby when native is selected without strict mode" do
        ENV["FONTISAN_ENGINE_STRICT"] = "0"
        out, err, status = result

        expect([status.success?, out]).to eq([true, "ruby"]), err
      end

      it "raises TierUnavailable when native is selected in strict mode" do
        out, err, status = result

        expect([status.success?, out]).to eq([true, "unavailable"]), err
      end
    end
  end
end
