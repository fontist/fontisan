# frozen_string_literal: true

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

    # Operations served natively. Convert, extract, instance and subset are in
    # the extension (`native_convert` ...) but are routed by card 2f.
    OPERATIONS = %i[read audit audit_dir scan].freeze

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
      def supports_options?(operation, options)
        case operation
        when :read then read_options?(options)
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

      def read_options?(options)
        return false unless options.keys.all? { |key| %i[mode lazy].include?(key) }

        %w[metadata full].include?(options.fetch(:mode, :metadata).to_s) &&
          [true, false].include?(options.fetch(:lazy, true))
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
        raise exception_class(class_name), message, cause: cause
      end

      def build_exception(name, text, cause)
        raise exception_class(name), text, cause: cause
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
