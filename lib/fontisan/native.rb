# frozen_string_literal: true

module Fontisan
  # The `:native` engine tier (Rust through magnus). The extension does not
  # exist yet, so the probe reports false; the contract below is what
  # {Fontisan::Engine} relies on and what the extension has to meet.
  #
  # Tier contract: `available?`, `supports?(operation, path)` and
  # `call(operation, *args, **kwargs)`.
  module Native
    EXTENSION = "fontisan/native/fontisan_native"
    ABI_VERSION = 1

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

      # @return [Boolean] whether the extension serves +operation+ for +path+
      def supports?(_operation, _path = nil)
        available?
      end

      def call(operation, *_args, **_kwargs)
        raise Fontisan::Error, "native tier cannot serve #{operation}: extension not loaded"
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
    end
  end
end
