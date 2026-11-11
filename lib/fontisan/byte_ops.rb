# frozen_string_literal: true

module Fontisan
  # Routing rules, result rebuilding and error rebuilding shared by the engine
  # tiers that serve convert, extract, instance and subset
  # ({Fontisan::Native}, {Fontisan::Ffi}). Included into their singleton
  # classes; the methods are private to the tier.
  module ByteOps
    # Convert target codes of the engine (extension and C ABI alike).
    TARGET_CODES = { ttf: 0, otf: 1, woff: 2, woff2: 3, ttc: 4, otc: 5 }.freeze
    SINGLE_TARGETS = %i[ttf otf woff woff2].freeze
    COLLECTION_TARGETS = %i[ttc otc woff2].freeze
    CONVERT_OPTIONS = %i[to output timestamp quiet].freeze
    SUBSET_PROFILES = %w[web pdf minimal].freeze
    MAX_CODEPOINT = 0x10FFFF
    # The engine's extract index is a u32; a larger one would wrap, not raise.
    MAX_FONT_INDEX = 0xFFFF_FFFF

    BYTE_OPERATIONS = %i[convert extract instance subset].freeze

    # "<ruby class>: <message>": how the engine reports a Ruby exception it
    # mirrors (the byte operations carry one class and one message, no chain).
    FAILURE_MESSAGE = /\A([A-Z]\w*(?:::\w+)*): (.*)\z/m
    # The engine's text for a file that is no font (convert adds a "Conversion
    # failed: " prefix); Ruby's is InvalidFontError.
    UNRECOGNISED_FORMAT_MESSAGE = "unrecognised font format"
    # Prefix of a convert failure that wraps the engine's own message.
    TRANSFORMATION_PREFIX = "Conversion failed: Transformation failed: "
    # Engine messages for bad font data that Ruby raises as InvalidFontError:
    # the WOFF/WOFF2 container decoders ("woff: ...", "woff2: ..."), and the
    # same error as its debug text.
    INVALID_FONT_MESSAGE = /\A(?:woff2?: |Error \{ class: InvalidFont, message: ")/
    # The instancer's own error; convert keeps Fontisan::Error for it, as Ruby does.
    TRUNCATED_TABLE_MESSAGE = "Static instancing: truncated or malformed table"
    DEBUG_ERROR_MESSAGE = /\AError \{ class: InvalidFont, message: "(.*)" \}\z/m

    private

    # Whether the engine honours +options+ for +operation+ (one of
    # {BYTE_OPERATIONS}); the first reuse point for tier routing.
    def byte_options?(operation, options, path)
      case operation
      when :convert then convert_options?(options, path)
      when :extract then extract_options?(options)
      when :instance then instance_options?(options, path)
      when :subset then subset_options?(options, path)
      else false
      end
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
        options[:index].between?(0, MAX_FONT_INDEX) && options[:output_dir].respond_to?(:to_str)
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

    # The output path of a convert, after the checks the Ruby tier makes before
    # it converts: never the input file, and its directory exists.
    def convert_output(path, output)
      output = File.path(output)
      OutputGuard.check!(path, output)
      dir = File.dirname(output)
      raise ArgumentError, "Output directory not found: #{dir}" unless File.directory?(dir)

      output
    end

    def finish_convert(path, target, output, bytes)
      write_output(output, bytes)
      result = { success: true, input_path: path, output_path: output }
      result.merge!(convert_formats(path, target))
      result.merge(input_size: File.size(path), output_size: bytes.bytesize,
                   **convert_tail(path))
    end

    # Writes as the Ruby tier's convert does: an IO failure is a Fontisan::Error.
    def write_output(output, bytes)
      File.binwrite(output, bytes)
    rescue SystemCallError => e
      raise Fontisan::Error, "Conversion failed: Transformation failed: #{e.message}"
    end

    def convert_formats(path, target)
      return { source_format: single_format(path), target_format: target } unless collection_file?(path)

      source = File.binread(path, 4) == "wOF2" ? :woff2_collection : :ttc
      { source_format: source, target_format: target == :woff2 ? :woff2_collection : target }
    end

    # Collections report `num_fonts`; single fonts the variation strategy
    # (an fvar font is converted as an instance, the rest are preserved).
    def convert_tail(path)
      return { num_fonts: collection_font_count(path) } if collection_file?(path)

      { variation_strategy: variable_font?(path) ? :instance : :preserve }
    end

    def single_format(path)
      FontLoader.detect_format(path)
    end

    # A WOFF2 collection is counted from its directory, not decoded: the
    # decode needs `brotli`, which the java platform (JRuby) does not have, and
    # the engine has already served the convert.
    def collection_font_count(path)
      if File.binread(path, 4) == "wOF2"
        return Woff2::CollectionDecoder.new(File.binread(path)).font_count
      end

      FontLoader.load_collection(path).num_fonts
    end

    def variable_font?(path)
      return woff2_tags(path).include?("fvar") if File.binread(path, 4) == "wOF2"

      font = FontLoader.load(path, mode: :metadata, lazy: true)
      font.has_table?("fvar")
    ensure
      font.close if font.respond_to?(:close)
    end

    # Table tags from the WOFF2 table directory, which is stored uncompressed
    # (no `brotli` needed, unlike loading the font).
    def woff2_tags(path)
      File.open(path, "rb") do |io|
        header = Woff2::Woff2Header.read(io)
        Woff2Font.read_table_directory_from_io(io, header).map(&:tag)
      end
    end

    def unix_seconds(timestamp)
      timestamp.respond_to?(:to_time) ? timestamp.to_time.to_i : Integer(timestamp)
    end

    # Raise the Ruby tier's exception: class, message and the cause chain
    # (each cause is raised so that its own #cause is set).
    def raise_failure(details, byte_operation: false)
      class_name, message, causes = details
      klass, message = byte_failure(class_name, message) if byte_operation
      klass ||= exception_class(class_name)
      raised, text = public_failure(klass, message)
      # The leaked Ruby error stays as the cause, as the Ruby tier's does.
      causes = [[class_name, message], *causes] unless raised == klass
      cause = nil
      causes.reverse_each { |name, detail| cause = build_exception(name, detail, cause) }
      raise build_instance(raised, text), cause: cause
    end

    # An engine error that mirrors a Ruby parser leak (EOFError, NoMethodError,
    # ...) is raised as the Ruby tier raises it now: InvalidFontError.
    def public_failure(klass, message)
      return [klass, message] unless Reference::PARSER_LEAKS.any? { |leak| klass <= leak }

      [InvalidFontError, Reference.malformed_message(klass, message)]
    end

    # The Ruby class and message of a failed byte operation, so that a tier
    # never changes what a caller can rescue or match: an engine error that
    # names the Ruby exception it mirrors ("RuntimeError: ...") is unwrapped,
    # and the engine's unrecognised-format error becomes the loader's.
    def byte_failure(class_name, message)
      if class_name == "Fontisan::Error" && (match = FAILURE_MESSAGE.match(message))
        class_name = match[1]
        message = match[2]
      end
      bare = message.delete_prefix(TRANSFORMATION_PREFIX)
      return [InvalidFontError, FontLoader::UNKNOWN_FORMAT_MESSAGE] if bare.delete_prefix("Conversion failed: ") == UNRECOGNISED_FORMAT_MESSAGE
      return [InvalidFontError, message] if message == TRUNCATED_TABLE_MESSAGE
      return [InvalidFontError, bare.sub(DEBUG_ERROR_MESSAGE, '\\1')] if class_name == "Fontisan::Error" && INVALID_FONT_MESSAGE.match?(bare)

      [exception_class(class_name), message]
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
