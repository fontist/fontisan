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
    ABI_VERSION = 1

    # Operations served natively. Convert, extract, instance and subset are
    # path-based only (card 2f): the object-based entry points
    # (`Subset::Builder.new(font, ...)`, `Variable::Instancer.new(font)`) are
    # not Reference operations, so they never reach a gate and stay on Ruby.
    OPERATIONS = %i[read audit audit_dir scan convert extract instance subset].freeze

    # Convert target codes of the extension (`Target::from_code`).
    TARGET_CODES = { ttf: 0, otf: 1, woff: 2, woff2: 3, ttc: 4, otc: 5 }.freeze
    SINGLE_TARGETS = %i[ttf otf woff woff2].freeze
    COLLECTION_TARGETS = %i[ttc otc woff2].freeze
    CONVERT_OPTIONS = %i[to output timestamp quiet].freeze
    SUBSET_PROFILES = %w[web pdf minimal].freeze
    MAX_CODEPOINT = 0x10FFFF

    # Raised by the extension for an engine failure; `details` is
    # `[class name, message, [[cause class, cause message], ...]]`.
    class Failure < StandardError
      attr_reader :details
    end

    # A Rust panic, caught in the extension and surfaced as a Ruby error.
    class Panic < Fontisan::Error; end

    class << self
      # Probe: true only when the extension loads and reports the ABI this
      # gem expects. Any load failure (missing library, missing symbol, ABI
      # mismatch, a broken loader) is a plain false, never an exception.
      def available?
        return @available if defined?(@available)

        @available = probe
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
        when :convert then convert_options?(options, path)
        when :extract then extract_options?(options)
        when :instance then instance_options?(options, path)
        when :subset then subset_options?(options, path)
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

      def load_extension
        require EXTENSION
      end

      def abi_version
        respond_to?(:extension_abi_version) ? extension_abi_version : nil
      end

      # A collection: `ttcf`, or a WOFF2 whose flavor is `ttcf`.
      def collection_file?(path)
        head = File.binread(path, 8) or return false
        head.start_with?("ttcf") || (head.start_with?("wOF2") && head.byteslice(4, 4) == "ttcf")
      rescue SystemCallError
        false
      end

      # `.otc` decision (card 2f): Ruby picks a collection's source type from
      # the input path's extension (`.otc` vs anything else), and the engine
      # only sees bytes and assumes `.ttc`. No hint is passed: `.otc`
      # inputs stay on the Ruby tier.
      def otc_hint?(path)
        File.extname(path).casecmp?(".otc")
      end

      # Single target `to:` (no multi-format), a format pair the engine
      # serves, no `coordinates:` / `preserve_hints` / compression knobs.
      # TODO(2f ffi): the :ffi tier reuses these checks unchanged.
      def convert_options?(options, path)
        return false unless options.keys.all? { |key| CONVERT_OPTIONS.include?(key) }
        return false unless options[:output].is_a?(String) || options[:output].respond_to?(:to_path)
        return false unless timestamp_option?(options[:timestamp])

        target = convert_target(options[:to]) or return false
        return false unless path.is_a?(String)
        return false if otc_hint?(path)

        (collection_file?(path) ? COLLECTION_TARGETS : SINGLE_TARGETS).include?(target)
      end

      def convert_target(value)
        return nil unless value.is_a?(Symbol) || value.is_a?(String)

        target = value.to_s.downcase.to_sym
        TARGET_CODES.key?(target) ? target : nil
      end

      def timestamp_option?(value)
        value.nil? || value.is_a?(Integer) || value.respond_to?(:to_time)
      end

      def extract_options?(options)
        options.keys.sort == %i[index output_dir] && options[:index].is_a?(Integer) &&
          !options[:index].negative? && options[:output_dir].respond_to?(:to_str)
      end

      def instance_options?(options, path)
        return false unless options.keys.all? { |key| %i[coords timestamp].include?(key) }
        return false unless options[:coords].is_a?(Hash) && !path.nil? && !collection_file?(path)

        options[:coords].all? { |tag, value| tag.to_s.bytesize == 4 && numeric?(value) }
      end

      def subset_options?(options, path)
        return false unless options.keys.all? { |key| %i[unicodes text profile timestamp].include?(key) }
        return false if path.nil? || collection_file?(path)
        return false unless SUBSET_PROFILES.include?(options.fetch(:profile, "web"))

        text = options[:text]
        return false unless text.nil? || text.is_a?(String)

        Array(options[:unicodes]).all? { |cp| cp.is_a?(Integer) && cp.between?(0, MAX_CODEPOINT) }
      end

      def numeric?(value)
        Float(value)
        true
      rescue ArgumentError, TypeError
        false
      end

      def read_options?(options)
        return false unless options.keys.all? { |key| %i[mode lazy].include?(key) }

        %w[metadata full].include?(options.fetch(:mode, :metadata).to_s) &&
          [true, false].include?(options.fetch(:lazy, true))
      end

      # Writes the converted font to +output+ and returns the ConvertCommand
      # result hash, rebuilt from the engine's bytes and the input header.
      # TODO(2f ffi): the ffi tier calls its own CONVERT op, then `finish_convert`.
      def convert(path, output:, timestamp: nil, **options)
        path = File.path(path)
        target = convert_target(options.fetch(:to))
        bytes = native_convert(path, TARGET_CODES.fetch(target), timestamp ? unix_seconds(timestamp) : Time.now.to_i)
        finish_convert(path, target, File.path(output), bytes)
      end

      def finish_convert(path, target, output, bytes)
        File.binwrite(output, bytes)
        result = { success: true, input_path: path, output_path: output }
        result.merge!(convert_formats(path, target))
        result.merge(input_size: File.size(path), output_size: bytes.bytesize,
                     **convert_tail(path))
      end

      def convert_formats(path, target)
        return { source_format: single_format(path), target_format: target } unless collection_file?(path)

        source = File.binread(path, 4) == "wOF2" ? :woff2_collection : :ttc
        { source_format: source, target_format: target == :woff2 ? :woff2_collection : target }
      end

      # Collections report `num_fonts`; single fonts the variation strategy
      # (an fvar font is converted as an instance, the rest are preserved).
      def convert_tail(path)
        return { num_fonts: FontLoader.load_collection(path).num_fonts } if collection_file?(path)

        { variation_strategy: variable_font?(path) ? :instance : :preserve }
      end

      def single_format(path)
        FontLoader.detect_format(path)
      end

      def variable_font?(path)
        font = FontLoader.load(path, mode: :metadata, lazy: true)
        font.has_table?("fvar")
      ensure
        font.close if font.respond_to?(:close)
      end

      def unix_seconds(timestamp)
        timestamp.respond_to?(:to_time) ? timestamp.to_time.to_i : Integer(timestamp)
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
          rel = row["path"].delete_prefix("#{dir}/")
          next if rel.split("/").any? { |part| part.start_with?(".") }

          dir_entry(row, rel, validate)
        end
      end

      def dir_entry(row, rel, validate)
        case row["status"]
        when "ok" then { "faces" => row["reports"], "path" => rel }
        when "unsupported" then audit_with_ruby(row["path"], rel, validate)
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

      # Raise the Ruby tier's exception: class, message and the cause chain
      # (each cause is raised so that its own #cause is set).
      def raise_failure(details)
        class_name, message, causes = details
        cause = nil
        causes.reverse_each { |name, text| cause = build_exception(name, text, cause) }
        raise build_instance(exception_class(class_name), message), cause: cause
      end

      # `klass.new(message)`, or the `message:` keyword form some Fontisan
      # errors use (MissingVariationTableError); never a failed constructor.
      def build_instance(klass, message)
        klass.new(message)
      rescue ArgumentError
        begin
          klass.new(message: message)
        rescue ArgumentError
          Fontisan::Error.new(message)
        end
      end

      def build_exception(name, text, cause)
        raise build_instance(exception_class(name), text), cause: cause
      rescue Exception => e # rubocop:disable Lint/RescueException
        e
      end

      def exception_class(name)
        klass = Object.const_get(name)
        klass.is_a?(Class) && klass <= Exception ? klass : Fontisan::Error
      rescue NameError
        Fontisan::Error
      end
    end
  end
end
