# frozen_string_literal: true

module Fontisan
  module Tables
    class Cff
      # CFF2 CharStringBuilder — extends the CFF1 charstring with
      # variable-font operators (vsindex, blend).
      #
      # In CFF2, the hmoveto operator (22) is repurposed as vsindex
      # (selects a VariationStore item), and a new blend operator
      # (23) applies variation deltas to the current operands.
      #
      # The blend protocol:
      #   1. Push n base values for the coordinates to vary
      #   2. Push n * num_regions delta values (axis-ordered)
      #   3. Emit blend → pops n*(num_regions+1), pushes n blended values
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/cff2#charstring-operators
      class Cff2CharStringBuilder < CharStringBuilder
        # CFF2 replaces hmoveto(22) with vsindex(22) — different role.
        # All other operators are shared with CFF1.
        OPERATORS_CFF2 = OPERATORS.merge(
          hmoveto: nil, # removed in CFF2
          vsindex: 22,         # variable-store subtable selector
          blend: 23,           # apply variation deltas
        )

        # Build a variable charstring from a UFO default outline plus
        # variation deltas from the variation masters.
        #
        # @param outline [Models::Outline] default-master outline
        # @param master_outlines [Array<Models::Outline>] variation masters
        # @param regions [Array<Hash>] variation regions (from fvar)
        # @param width [Integer, nil] advance width
        # @return [String] CFF2 charstring bytes with blend sequences
        def self.build_variable(outline, master_outlines:, regions:, width: nil)
          io = StringIO.new("".b)
          io.set_encoding(Encoding::BINARY)
          builder = new(io)
          builder.write_width(width) if width
          builder.write_variable_outline(outline, master_outlines, regions)
          builder.write_endchar
          io.string
        end

        # Append a charstring segment that includes the blend operators.
        # Each on-curve point's coordinates are emitted as
        #   base deltas[0] deltas[1] ... deltas[r] blend
        # where r = regions.size.
        def write_variable_path(path, master_paths, regions)
          num_regions = regions.size
          return write_path(path) if num_regions.zero?

          path.contours.sum { |c| c.points.size * 2 }
          true

          path.contours.each_with_index do |contour, ci|
            if ci.zero?
              if contour.points.first.type == "line"
                write_rmoveto(contour.points.first.x, contour.points.first.y)
              else
                write_hmoveto(contour.points.first.x)
                write_vmoveto(contour.points.first.y)
              end
            end

            segments = contour.points.drop(1).each_slice(1).map(&:first)
            segments.each do |point|
              master_points = master_paths.map { |mp| mp.contours[ci].points[segments.index(point) + 1] }
              deltas = master_points.zip(master_paths).map do |mp, _master|
                dx = (mp.x - point.x).to_i
                dy = (mp.y - point.y).to_i
                [dx, dy]
              end.flatten
              write_number(point.x)
              write_number(point.y)
              deltas.each { |d| write_number(d) }
              write_operator(:blend)
            end
          end
        end

        def write_vsindex(index)
          write_number(index)
          write_operator(:vsindex)
        end

        def write_blend(_count, deltas)
          # Caller pushes the n base values, then this emits the deltas
          # followed by the blend operator.
          deltas.each { |d| write_number(d) }
          write_operator(:blend)
        end

        def write_variable_outline(outline, master_outlines, regions)
          write_variable_path(outline, master_outlines, regions)
        end

        def write_operator(operator)
          if OPERATORS_CFF2.key?(operator) && !OPERATORS_CFF2[operator].nil?
            @output.putc(OPERATORS_CFF2[operator])
          elsif TWO_BYTE_OPERATORS.key?(operator)
            bytes = TWO_BYTE_OPERATORS[operator]
            @output.putc(bytes[0])
            @output.putc(bytes[1])
          else
            raise ArgumentError, "Unknown CFF2 operator: #{operator}"
          end
        end
      end
    end
  end
end
