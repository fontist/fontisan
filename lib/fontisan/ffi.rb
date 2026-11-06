# frozen_string_literal: true

require "fileutils"
require "json"
require "rbconfig"
require "fontisan/ffi_platform"

module Fontisan
  # The `:ffi` engine tier: the Rust engine's C ABI (fontisan.h, version 1)
  # loaded through the optional `ffi` gem. It serves the read-side
  # {Fontisan::Reference} operations (read, audit, audit_dir, scan) and the
  # byte operations (convert, extract, instance, subset: card 2f-ffi, the same
  # routing rules as {Fontisan::Native} through {Fontisan::ByteOps}); every
  # other operation, and dfont / Type 1 files, are the Ruby tier's.
  #
  # The C ABI has no glyph-id operation: a subset's glyph ids come from the
  # Ruby facade's `glyph_ids` (a pure cmap read, run on the Ruby tier).
  #
  # The `ffi` gem and the shared library are loaded lazily, on the first probe.
  # A missing gem, missing or unloadable library, missing symbol or ABI
  # mismatch makes {.available?} false and never raises.
  #
  # The library is looked up in FONTISAN_CDYLIB (a file path), then in
  # lib/fontisan/ffi/<platform>/ (the java-platform gem, one directory per
  # bundled OS and architecture, see {FfiPlatform}), then in lib/fontisan/ffi/
  # (the platform gems).
  #
  # Tier contract: `available?`, `supports?(operation, path)` and
  # `call(operation, *args, **kwargs)`, as for {Fontisan::Native}.
  module Ffi
    class AbiMismatch < Fontisan::Error; end

    LIBRARY = "fontisan_cdylib"
    OPERATIONS = %i[read audit audit_dir scan convert extract instance subset].freeze
    RUBY_ONLY_FORMATS = %i[dfont pfa pfb].freeze

    OP_CONVERT = 1
    OP_EXTRACT = 2
    OP_SUBSET = 6
    OP_INSTANCE = 7
    OP_READ = 8
    OP_AUDIT = 9
    OP_SCAN = 10
    OP_AUDIT_DIR = 11
    FLAG_METADATA = 1
    FLAG_LAZY = 2
    FLAG_VALIDATE = 1

    CONVERT_FAILED = 8
    SUBSET_PROFILE_CODES = { "pdf" => 0, "web" => 1, "minimal" => 2 }.freeze
    FIXED_ONE = 65_536

    class << self
      include ByteOps

      # Probe: true only when the `ffi` gem and a compatible library both load.
      def available?
        return @available if defined?(@available)

        @available = probe
      end

      # Forget the memoised probe and the loaded library.
      def reset!
        @client = nil
        remove_instance_variable(:@available) if defined?(@available)
      end

      # Whether this tier serves +operation+ for +path+: the read-side
      # operations on anything but dfont and Type 1 files.
      def supports?(operation, path = nil)
        return false unless available? && OPERATIONS.include?(operation)

        case operation
        when *ByteOps::BYTE_OPERATIONS then path.is_a?(String) && File.file?(path) && !ruby_only?(path)
        when :audit_dir then path.nil? || File.directory?(path)
        when :scan then path.nil? || File.file?(path) && !ruby_only?(path)
        else path.nil? || !ruby_only?(path)
        end
      end

      # Options the engine honours; anything else is served by Ruby. The
      # read-side operations check their own options and fall back inside.
      def supports_options?(operation, options, path = nil)
        return byte_options?(operation, options, path) if ByteOps::BYTE_OPERATIONS.include?(operation)

        OPERATIONS.include?(operation)
      end

      def call(operation, *, **)
        raise Fontisan::Error, "ffi tier cannot serve #{operation}" unless OPERATIONS.include?(operation)
        raise Fontisan::Error, "ffi tier cannot serve #{operation}: library not loaded" unless available?

        __send__(:"serve_#{operation}", *, **)
      end

      private

      attr_reader :client

      def probe
        require "fontisan/ffi/client"
        path = library_path or return false
        @client = Client.new(path)
        true
      rescue StandardError, ScriptError
        @client = nil
        false
      end

      def library_path
        override = ENV.fetch("FONTISAN_CDYLIB", "").strip
        return override unless override.empty?

        extension = case RbConfig::CONFIG["host_os"]
                    when /darwin/ then "dylib"
                    when /mswin|mingw|cygwin/ then "dll"
                    else "so"
                    end
        prefix = extension == "dll" ? "" : "lib"
        file = "#{prefix}#{LIBRARY}.#{extension}"
        platform = FfiPlatform.dir
        bundled = platform && File.expand_path("ffi/#{platform}/#{file}", __dir__)
        bundled && File.file?(bundled) ? bundled : File.expand_path("ffi/#{file}", __dir__)
      end

      def ruby_only?(path)
        RUBY_ONLY_FORMATS.include?(FontLoader.detect_format(path))
      rescue StandardError
        false
      end

      # Writes the converted font to +output+; returns the ConvertCommand hash.
      def serve_convert(path, output:, timestamp: nil, **options)
        path = File.path(path)
        target = convert_target(options.fetch(:to))
        stamp = timestamp ? unix_seconds(timestamp) : Time.now.to_i
        prefix = [ByteOps::TARGET_CODES.fetch(target), 0, stamp].pack("NNq>")
        bytes = byte_op(OP_CONVERT, prefix + File.binread(path))
        finish_convert(path, target, File.path(output), bytes)
      end

      # Same file layout as UnpackCommand: <output_dir>/<basename>.
      def serve_extract(path, index:, output_dir:)
        payload = byte_op(OP_EXTRACT, [index, 0, 0, 0].pack("NNNN") + File.binread(File.path(path)))
        length = payload.unpack1("N")
        name = payload.byteslice(4, length).force_encoding(Encoding::UTF_8)
        FileUtils.mkdir_p(output_dir)
        File.join(output_dir, name).tap { |out| File.binwrite(out, payload.byteslice(4 + length..)) }
      end

      def serve_instance(path, coords:, timestamp: nil)
        _ = timestamp
        axes = coords.map { |tag, value| tag.to_s.b + [(Float(value) * FIXED_ONE).round].pack("l>") }
        byte_op(OP_INSTANCE, [axes.size].pack("N") + axes.join + File.binread(File.path(path)))
      end

      def serve_subset(path, unicodes: nil, text: nil, profile: "web", timestamp: nil)
        _ = timestamp
        path = File.path(path)
        gids = ruby(:glyph_ids, path, unicodes: unicodes, text: text)
        head = [SUBSET_PROFILE_CODES.fetch(profile.to_s), gids.size, 0, 0].pack("NNNN")
        byte_op(OP_SUBSET, head + gids.pack("N*") + File.binread(path))
      end

      # The payload of a byte operation; a failure is raised as the Ruby
      # exception the message names (the ABI carries no cause chain).
      def byte_op(operation, input)
        reply = client.call(operation, input)
        return reply.payload if reply.status == Client::OK

        raise_byte_failure(reply)
      end

      def raise_byte_failure(reply)
        match = ByteOps::FAILURE_MESSAGE.match(reply.message)
        if reply.status == CONVERT_FAILED && match
          klass, message = byte_failure(match[1], match[2])
          raise build_instance(klass, message)
        end

        raise Fontisan::Error, "fontisan ffi status #{reply.status}: #{reply.message}"
      end

      def serve_read(path, mode: :metadata, lazy: true)
        return ruby(:read, path, mode: mode, lazy: lazy) unless %i[metadata full].include?(mode)

        path = reference_path(path)
        flags = (mode == :metadata ? FLAG_METADATA : 0) | (lazy ? FLAG_LAZY : 0)
        reply = client.call(OP_READ, File.binread(path), flags)
        return ruby(:read, path, mode: mode, lazy: lazy) if reply.status == Client::UNSUPPORTED

        rows(reply)
      end

      def serve_audit(path, validate: false)
        return ruby(:audit, path, validate: validate) unless [true, false, nil].include?(validate)

        path = reference_path(path)
        input = [File.basename(path).bytesize].pack("N") + File.basename(path).b + File.binread(path)
        reply = client.call(OP_AUDIT, input, validate ? FLAG_VALIDATE : 0)
        return ruby(:audit, path, validate: validate) if reply.status == Client::UNSUPPORTED

        rows(reply)
      end

      def serve_scan(paths)
        Array(paths).flat_map do |path|
          reply = client.call(OP_SCAN, File.path(path))
          result = reply.status == Client::OK ? decode(reply.payload) : nil
          result = nil if result&.any? { |row| row["status"] == "unsupported" }
          # "status" is the engine's routing marker; Reference rows have none.
          result ? result.map { |row| row.except("status") } : ruby(:scan, [path])
        end
      end

      def serve_audit_dir(dir, validate: false)
        return ruby(:audit_dir, dir, validate: validate) unless [true, false, nil].include?(validate)

        dir = reference_path(dir)
        reply = client.call(OP_AUDIT_DIR, dir, validate ? FLAG_VALIDATE : 0)
        raise Fontisan::Error, reply.message unless reply.status == Client::OK

        decode(reply.payload).filter_map { |row| dir_entry(dir, row, validate) }
      end

      def dir_entry(dir, row, validate)
        rel = Reference.relative_row_path(dir, row["path"])
        # Like the Ruby and native tiers: nothing below a hidden directory.
        return if rel.split("/").any? { |part| part.start_with?(".") }

        seen_by(File.join(dir, rel), :ffi)
        case row["status"]
        when "ok" then { "path" => rel, "faces" => row["reports"] }
        when "error" then { "path" => rel, "error" => row["error"].slice("class", "message") }
        else ruby_entry(dir, rel, validate)
        end
      end

      # A file the engine does not read (dfont, Type 1): the Ruby tier audits it.
      def ruby_entry(dir, rel, validate)
        file = File.join(dir, rel)
        seen_by(file, :ruby)
        { "path" => rel, "faces" => Reference.normalize(Engine.ruby_call(:audit, file, validate: validate)) }
      rescue StandardError => e
        { "path" => rel, "error" => { "class" => e.class.name, "message" => e.message } }
      end

      def seen_by(file, tier)
        recorder = Thread.current[Engine::ROW_RECORDER]
        recorder[file] = tier if recorder
      end

      def reference_path(path)
        Reference.__send__(:path_arg, path)
      end

      def ruby(operation, ...)
        Engine.ruby_call(operation, ...)
      end

      # The rows of a successful read/audit reply, or the Ruby exception the
      # engine reports for a failed one.
      def rows(reply)
        case reply.status
        when Client::OK then decode(reply.payload)
        when Client::READ_FAILED then raise_reported(JSON.parse(reply.message))
        else raise Fontisan::Error, "fontisan ffi status #{reply.status}: #{reply.message}"
        end
      end

      # Packed rows: u32 BE count, then per row u32 BE length + UTF-8 JSON.
      def decode(payload)
        count, = payload.unpack("N")
        offset = 4
        Array.new(count) do
          length = payload.byteslice(offset, 4).unpack1("N")
          row = JSON.parse(payload.byteslice(offset + 4, length))
          offset += 4 + length
          row
        end
      end

      # Raise the reported error as its Ruby class, message and cause chain.
      def raise_reported(report)
        raise_chain([report.slice("class", "message"),
                     *Array(report["causes"])])
      end

      def raise_chain(infos)
        info, *rest = infos
        return raise(build_error(info)) if rest.empty?

        begin
          raise_chain(rest)
        rescue StandardError => e
          raise build_error(info), cause: e
        end
      end

      def build_error(info)
        klass = begin
          Object.const_get(info["class"])
        rescue NameError
          nil
        end
        return Fontisan::Error.new("#{info['class']}: #{info['message']}") unless klass.is_a?(Class) && klass <= StandardError

        error = klass.new(info["message"])
        return error if error.message == info["message"]

        # Errno classes prefix their text; the report already carries it whole.
        error.define_singleton_method(:message) { info["message"] }
        error
      end
    end
  end
end
