# frozen_string_literal: true

require "fileutils"

module Fontisan
  # The `:native` engine tier: the fontisan-rs engine through a magnus
  # extension (`ext/fontisan_native`, built by rb-sys).
  #
  # Tier contract (see {Fontisan::Engine}): `available?`,
  # `supports?(operation, path)`, `supports_options?(operation, kwargs)` and
  # `call(operation, *args, **kwargs)`.
  #
  # The extension returns the same Hash / Array / String shapes as
  # {Fontisan::Reference}: it walks the engine's documents straight into Ruby
  # objects (no JSON text on either side), with the GVL released around each
  # engine call. A failure arrives as {Failure}; {.call} rebuilds the Ruby
  # tier's exception class, message and cause chain from it.
  module Native
    EXTENSION = "fontisan/native/fontisan_native"
    # Cross-compiled platform gems ship one build per Ruby minor, in a
    # directory named for it (rake-compiler's fat-binary layout).
    VERSIONED_EXTENSION = "fontisan/native/#{RUBY_VERSION[/\A\d+\.\d+/]}/fontisan_native".freeze
    ABI_VERSION = 1

    # Operations served natively. Convert, extract, instance and subset are
    # path-based only (card 2f): the object-based entry points
    # (`Subset::Builder.new(font, ...)`, `Variable::Instancer.new(font)`) are
    # not Reference operations, so they never reach a gate and stay on Ruby.
    OPERATIONS = %i[read audit audit_dir scan convert extract instance subset].freeze

    # Raised by the extension for an engine failure; `details` is
    # `[class name, message, [[cause class, cause message], ...]]`.
    class Failure < StandardError
      attr_reader :details
    end

    # A Rust panic, caught in the extension and surfaced as a Ruby error.
    class Panic < Fontisan::Error; end

    class << self
      include ByteOps

      # Probe: true only when the extension loads and reports the ABI this
      # gem expects. Any load failure (missing library, missing symbol, ABI
      # mismatch, a broken loader) is a plain false, never an exception.
      def available?
        return @available if defined?(@available)

        @available = probe.tap { |ok| warn_unusable unless ok }
      end

      # Forget the memoised probe (tests, or after installing the extension).
      def reset!
        remove_instance_variable(:@available) if defined?(@available)
      end

      # @return [Boolean] whether the extension serves +operation+ for +path+.
      #   dfont and Type 1 files, missing files and non-directories (for
      #   audit_dir) stay with the Ruby tier.
      def supports?(operation, path = nil)
        return false unless available? && OPERATIONS.include?(operation)
        return false unless path.is_a?(String)

        case operation
        when :audit_dir then File.directory?(path)
        when :scan then File.file?(path) && native_supports_file(path)
        else native_supports_file(path)
        end
      end

      # Options the extension honours; anything else is served by Ruby.
      # +path+ is the call's input path (the Engine passes it when this method
      # takes a third argument): collection inputs and the `.otc` hint decide
      # some of the byte ops.
      def supports_options?(operation, options, path = nil)
        case operation
        when :read then read_options?(options)
        when *ByteOps::BYTE_OPERATIONS then byte_options?(operation, options, path)
        when :audit, :audit_dir then options.keys.all?(:validate) && [true, false, nil].include?(options[:validate])
        when :scan then options.empty?
        else false
        end
      end

      def call(operation, *, **)
        case operation
        when :read then read(*, **)
        when :audit then audit(*, **)
        when :audit_dir then audit_dir(*, **)
        when :scan then scan(*)
        when :convert then convert(*, **)
        when :extract then extract(*, **)
        when :instance then instance(*, **)
        when :subset then subset(*, **)
        else raise Fontisan::Error, "native tier cannot serve #{operation}"
        end
      rescue Failure => e
        raise_failure(e.details)
      end

      private

      def probe
        load_extension
        abi_version == ABI_VERSION
      rescue StandardError, ScriptError
        false
      end

      # An extension file that is shipped but does not load or report the
      # expected ABI leaves every call on the Ruby tier. Say so once; the
      # fallback itself is unchanged. No file at all (a source install without
      # cargo) is the normal :ruby gem and stays quiet.
      def warn_unusable
        return if @warned_unusable || !extension_present?

        @warned_unusable = true
        warn "fontisan: the native extension is present but did not load (or has the wrong ABI); " \
             "falling back to the Ruby tier. Reinstall the gem or run `bundle exec rake compile`."
      end

      def extension_present?
        [VERSIONED_EXTENSION, EXTENSION].any? { |feature| $LOAD_PATH.resolve_feature_path(feature) }
      end

      def load_extension
        require VERSIONED_EXTENSION
      rescue LoadError
        require EXTENSION
      end

      def abi_version
        respond_to?(:extension_abi_version) ? extension_abi_version : nil
      end

      def read_options?(options)
        return false unless options.keys.all? { |key| %i[mode lazy].include?(key) }

        %w[metadata full].include?(options.fetch(:mode, :metadata).to_s) &&
          [true, false].include?(options.fetch(:lazy, true))
      end

      # Writes the converted font to +output+ and returns the ConvertCommand
      # result hash, rebuilt from the engine's bytes and the input header.
      def convert(path, output:, timestamp: nil, **options)
        path = File.path(path)
        target = convert_target(options.fetch(:to))
        bytes = native_convert(path, ByteOps::TARGET_CODES.fetch(target), timestamp ? unix_seconds(timestamp) : Time.now.to_i)
        finish_convert(path, target, File.path(output), bytes)
      end

      # Same file layout as UnpackCommand: <output_dir>/<basename>.
      def extract(path, index:, output_dir:)
        name, bytes = native_extract(File.path(path), index)
        FileUtils.mkdir_p(output_dir)
        File.join(output_dir, name).tap { |out| File.binwrite(out, bytes) }
      end

      def instance(path, coords:, timestamp: nil)
        _ = timestamp
        values = coords.to_h { |tag, value| [tag.to_s, Float(value)] }
        native_instance(File.path(path), values.to_a)
      end

      def subset(path, unicodes: nil, text: nil, profile: "web", timestamp: nil)
        _ = timestamp
        path = File.path(path)
        codepoints = Array(unicodes).map(&:to_i) + text.to_s.codepoints
        gids = native_glyph_ids(path, codepoints, File.basename(path))
        native_subset(path, gids, profile.to_s)
      end

      def read(path, mode: :metadata, lazy: true)
        native_read(File.path(path), mode.to_s == "metadata", lazy)
      end

      def audit(path, validate: false)
        native_audit(File.path(path), validate ? true : false)
      end

      def scan(paths)
        Array(paths).flat_map { |path| native_scan(File.path(path)) }
      end

      # Same entries as Reference.audit_dir. A file the engine leaves to Ruby
      # (dfont, Type 1) is audited through the gate, so it is served and
      # recorded as :ruby.
      def audit_dir(dir, validate: false)
        dir = File.path(dir)
        native_audit_dir_rows(dir, validate ? true : false).filter_map do |row|
          rel = Fontisan::Reference.relative_row_path(dir, row["path"])
          next if rel.split("/").any? { |part| part.start_with?(".") }

          dir_entry(dir, row, rel, validate)
        end
      end

      def dir_entry(dir, row, rel, validate)
        case row["status"]
        when "ok" then { "faces" => row["reports"], "path" => rel }
        # The gate records the path it is given and Engine.audit_dir looks it up
        # as File.join(dir, rel); the row's own path has a native separator on
        # Windows, so it would never match.
        when "unsupported" then audit_with_ruby(File.join(dir, rel), rel, validate)
        else
          error = row["error"]
          { "error" => { "class" => error["class"], "message" => error["message"] }, "path" => rel }
        end
      end

      def audit_with_ruby(file, rel, validate)
        { "faces" => Fontisan::Reference.audit(file, validate: validate), "path" => rel }
      rescue StandardError => e
        { "error" => { "class" => e.class.name, "message" => e.message }, "path" => rel }
      end
    end
  end
end
