# frozen_string_literal: true

module Fontisan
  module SvgToGlyf
    module Path
      # Tokenizes an SVG path `d` attribute string and groups the
      # tokens into typed Command objects, handling implicit command
      # repetition.
      #
      # Arc (A/a) is not supported — ucode chart SVGs use cubic
      # curves exclusively. Encountering A raises a clear ArgumentError.
      module Parser
        COMMAND_RE = /[MmLlHhVvCcSsQqTtAaZz]/
        NUMBER_RE = /[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/
        TOKEN_RE = /#{COMMAND_RE}|#{NUMBER_RE}/

        # Expected argument count per command letter.
        ARITY = {
          "M" => 2, "L" => 2, "H" => 1, "V" => 1,
          "C" => 6, "S" => 4, "Q" => 4, "T" => 2,
          "Z" => 0
        }.freeze

        # @param d_string [String] SVG path data
        # @return [Array<Command>]
        def self.parse(d_string)
          tokens = tokenize(d_string)
          group_into_commands(tokens)
        end

        def self.tokenize(d_string)
          d_string.to_s.scan(TOKEN_RE).map do |tok|
            COMMAND_RE.match?(tok) ? [:command, tok] : [:number, tok.to_f]
          end
        end

        # Walk the token stream. After a command letter, consume its
        # arity's worth of numbers per command; extra numbers repeat
        # the command. After M/m, subsequent pairs become implicit L/l.
        def self.group_into_commands(tokens)
          commands = []
          current = nil
          args = []

          tokens.each do |type, value|
            if type == :command
              check_arc!(value)
              if value.upcase == "Z"
                commands << build_command(value, [])
                current = nil
              else
                current = value
              end
              args = []
              next
            end

            next unless current

            arity = ARITY.fetch(current.upcase)
            args << value

            next unless args.size >= arity

            commands << build_command(current, args.shift(arity))
            current = implicit_repeat_letter(current) if current.upcase == "M"
          end

          commands
        end

        def self.build_command(letter, args)
          Command.new(
            type: letter.upcase.to_sym,
            absolute: letter == letter.upcase,
            args: args,
          )
        end

        # After M/m, subsequent coordinate pairs become L/l (SVG spec).
        def self.implicit_repeat_letter(letter)
          letter == letter.upcase ? "L" : "l"
        end

        def self.check_arc!(letter)
          return unless letter && letter.upcase == "A"

          raise ArgumentError,
                "SVG arc command (A/a) is not supported by SvgToGlyf. " \
                "Convert arcs to cubic curves first."
        end

        private_class_method :tokenize, :group_into_commands, :build_command,
                             :implicit_repeat_letter, :check_arc!
      end
    end
  end
end
