# frozen_string_literal: true

module Fontisan
  # The `:ffi` engine tier (Rust cdylib through the optional `ffi` gem). No
  # cdylib exists yet, so the probe reports false. Same tier contract as
  # {Fontisan::Native}.
  module Ffi
    LIBRARY = "fontisan_cdylib"

    class << self
      # Probe: true only when the `ffi` gem and the cdylib both load. Any
      # failure is a plain false, never an exception.
      def available?
        return @available if defined?(@available)

        @available = probe
      end

      def reset!
        remove_instance_variable(:@available) if defined?(@available)
      end

      def supports?(_operation, _path = nil)
        available?
      end

      def call(operation, *_args, **_kwargs)
        raise Fontisan::Error, "ffi tier cannot serve #{operation}: library not loaded"
      end

      private

      def probe
        load_library
        true
      rescue StandardError, ScriptError
        false
      end

      # Placeholder until the cdylib ships: nothing to load yet.
      def load_library
        raise LoadError, "#{LIBRARY} is not built"
      end
    end
  end
end
