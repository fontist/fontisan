# frozen_string_literal: true

module Fontisan
  # Refuses to write a conversion over the font it reads.
  #
  # The output is compared with the input after symlinks and `..` are resolved
  # (a symlink to the input, or `dir/../input`, is the input). Every engine tier
  # calls this before it converts, so none of them overwrites its own input.
  module OutputGuard
    # The output path is the input file.
    class Refused < Error; end

    module_function

    # @param input [String, #to_path] the font being read
    # @param output [String, #to_path] where the result would be written
    # @raise [Refused] when both name the same file
    # @return [void]
    def check!(input, output)
      source = resolve(File.path(input))
      return if source.nil?
      return unless resolve(File.path(output)) == source

      raise Refused, "Output path #{File.path(output).inspect} is the input file " \
                     "#{File.path(input).inspect}; refusing to overwrite it"
    end

    # The real path of +path+; for a file that does not exist yet, the real
    # directory plus the file name. nil when neither can be resolved.
    def resolve(path)
      File.realpath(path)
    rescue SystemCallError
      begin
        File.join(File.realpath(File.dirname(path)), File.basename(path))
      rescue SystemCallError
        nil
      end
    end
  end
end
