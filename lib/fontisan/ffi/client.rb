# frozen_string_literal: true

require "ffi"

module Fontisan
  module Ffi
    # One loaded copy of the cdylib: the C structs of fontisan.h (ABI 1) and
    # the three exported functions. Only this file requires the optional `ffi`
    # gem, and only {Fontisan::Ffi} requires this file.
    class Client
      MAGIC = 0x4E415346 # "FSAN"
      ABI_VERSION = 1

      OK = 0
      INVALID_ARG = 7
      READ_FAILED = 9
      UNSUPPORTED = 10

      # The result block of one call; its pointers die with {#close}.
      Reply = Struct.new(:status, :payload, :message)

      class Header < FFI::Struct
        layout :magic, :uint32, :abi_version, :uint32, :struct_size, :uint32,
               :reserved, :uint32
      end

      class Request < FFI::Struct
        layout :header, Header, :op, :uint32, :flags, :uint32,
               :input, :pointer, :input_len, :size_t
      end

      class ErrorRow < FFI::Struct
        layout :code, :int32, :message, :pointer, :message_len, :size_t
      end

      class Result < FFI::Struct
        layout :header, Header, :status, :int32, :error, ErrorRow,
               :payload, :pointer, :payload_len, :size_t
      end

      # @raise [LoadError] when the library or one of its symbols is missing
      # @raise [Fontisan::Ffi::AbiMismatch] when it speaks another ABI version
      def initialize(path)
        @binding = Module.new do
          extend FFI::Library

          ffi_lib path
          attach_function :fontisan_abi_version, [], :uint32
          attach_function :fontisan_call, %i[pointer pointer], :int32
          attach_function :fontisan_result_free, [:pointer], :void
        end
        found = @binding.fontisan_abi_version
        return if found == ABI_VERSION

        raise AbiMismatch, "#{path} speaks ABI #{found}, this gem expects #{ABI_VERSION}"
      rescue FFI::NotFoundError => e
        raise LoadError, e.message
      end

      # Run one operation.
      #
      # @param operation [Integer] a FONTISAN_OP_* number
      # @param input [String] the request bytes
      # @param flags [Integer]
      # @return [Reply]
      def call(operation, input, flags = 0)
        input = input.b
        buffer = FFI::MemoryPointer.new(:uint8, [input.bytesize, 1].max)
        buffer.put_bytes(0, input)
        out = FFI::MemoryPointer.new(:pointer)
        @binding.fontisan_call(request(operation, flags, buffer, input.bytesize), out)
        read_result(out.read_pointer)
      end

      private

      def request(operation, flags, buffer, length)
        req = Request.new
        req[:header][:magic] = MAGIC
        req[:header][:abi_version] = ABI_VERSION
        req[:header][:struct_size] = Request.size
        req[:header][:reserved] = 0
        req[:op] = operation
        req[:flags] = flags
        req[:input] = buffer
        req[:input_len] = length
        req
      end

      def read_result(pointer)
        raise Fontisan::Error, "fontisan_call returned no result block" if pointer.null?

        result = Result.new(pointer)
        Reply.new(result[:status], bytes(result[:payload], result[:payload_len]),
                  bytes(result[:error][:message], result[:error][:message_len])
                    .force_encoding(Encoding::UTF_8))
      ensure
        @binding.fontisan_result_free(pointer) unless pointer.null?
      end

      def bytes(pointer, length)
        return "".b if pointer.null? || length.zero?

        pointer.read_bytes(length)
      end
    end
  end
end
