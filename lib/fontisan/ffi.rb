# frozen_string_literal: true

require "json"

module Fontisan
  # The `:ffi` engine tier: the Rust engine's C ABI (fontisan.h, version 1)
  # loaded through the optional `ffi` gem. It serves the read-side
  # {Fontisan::Reference} operations (read, audit, audit_dir, scan); every
  # other operation, and dfont / Type 1 files, are the Ruby tier's.
  #
  # The `ffi` gem and the shared library are loaded lazily, on the first probe.
  # A missing gem, missing or unloadable library, missing symbol or ABI
  # mismatch makes {.available?} false and never raises.
  #
  # The library is looked up in FONTISAN_CDYLIB (a file path), then in
  # lib/fontisan/ffi/.
  #
  # Tier contract: `available?`, `supports?(operation, path)` and
  # `call(operation, *args, **kwargs)`, as for {Fontisan::Native}.
  module Ffi
    class AbiMismatch < Fontisan::Error; end

    LIBRARY = "fontisan_cdylib"
    OPERATIONS = %i[read audit audit_dir scan].freeze
    RUBY_ONLY_FORMATS = %i[dfont pfa pfb].freeze

    OP_READ = 8
    OP_AUDIT = 9
    OP_SCAN = 10
    OP_AUDIT_DIR = 11
    FLAG_METADATA = 1
    FLAG_LAZY = 2
    FLAG_VALIDATE = 1

    class << self
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
        when :audit_dir then path.nil? || File.directory?(path)
        when :scan then path.nil? || File.file?(path) && !ruby_only?(path)
        else path.nil? || !ruby_only?(path)
        end
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
        File.expand_path("ffi/#{prefix}#{LIBRARY}.#{extension}", __dir__)
      end

      def ruby_only?(path)
        RUBY_ONLY_FORMATS.include?(FontLoader.detect_format(path))
      rescue StandardError
        false
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

        decode(reply.payload).map { |row| dir_entry(dir, row, validate) }
      end

      def dir_entry(dir, row, validate)
        rel = row["path"].delete_prefix("#{dir.chomp('/')}/")
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
