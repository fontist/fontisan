# frozen_string_literal: true

module Fontisan
  module SvgToGlyf
    module Geometry
      # Parses an SVG `transform="..."` attribute string into a single
      # AffineTransform representing the accumulated composition.
      #
      # Supports all six SVG transform functions:
      #   translate, scale, rotate, matrix, skewX, skewY
      #
      # Multiple functions compose left-to-right (leftmost is applied
      # last to the point), matching the SVG specification.
      module TransformParser
        FUNCTION_RE = /(\w+)\s*\(([^)]*)\)/

        # @param transform_string [String, nil] the SVG transform attribute
        # @return [AffineTransform]
        def self.parse(transform_string)
          return AffineTransform.identity if transform_string.nil? || transform_string.strip.empty?

          transforms = transform_string.scan(FUNCTION_RE).map do |name, args|
            build_transform(name, args)
          end
          transforms.reduce(AffineTransform.identity) { |acc, t| acc.compose(t) }
        end

        def self.build_transform(name, args_string)
          args = parse_args(args_string)
          case name
          when "translate" then build_translate(args)
          when "scale" then build_scale(args)
          when "rotate" then build_rotate(args)
          when "matrix" then build_matrix(args)
          when "skewX" then AffineTransform.skew_x_radians(degrees_to_radians(args.fetch(0)))
          when "skewY" then AffineTransform.skew_y_radians(degrees_to_radians(args.fetch(0)))
          else
            raise ArgumentError, "unknown SVG transform function: #{name.inspect}"
          end
        end

        def self.build_translate(args)
          AffineTransform.translate(args.fetch(0, 0), args.fetch(1, 0))
        end

        def self.build_scale(args)
          sx = args.fetch(0, 1)
          sy = args.fetch(1, sx)
          AffineTransform.scale(sx, sy)
        end

        def self.build_rotate(args)
          angle = args.fetch(0)
          return AffineTransform.rotate_degrees(angle) if args.size < 3

          cx = args.fetch(1)
          cy = args.fetch(2)
          around_point(AffineTransform.rotate_degrees(angle), cx, cy)
        end

        def self.build_matrix(args)
          raise ArgumentError, "matrix() requires 6 arguments, got #{args.size}" if args.size != 6

          AffineTransform.new(args[0], args[1], args[2], args[3], args[4], args[5])
        end

        # Rotate around a specific point: translate to origin, rotate,
        # translate back.
        def self.around_point(rotation, cx, cy)
          AffineTransform.translate(cx, cy)
            .compose(rotation)
            .compose(AffineTransform.translate(-cx, -cy))
        end

        # Parse comma/whitespace-separated numbers from a function arg list.
        def self.parse_args(args_string)
          args_string.to_s.scan(/[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/)
            .map(&:to_f)
        end

        def self.degrees_to_radians(degrees)
          degrees.to_f * Math::PI / 180.0
        end

        private_class_method :build_transform, :build_translate, :build_scale,
                             :build_rotate, :build_matrix, :around_point,
                             :parse_args, :degrees_to_radians
      end
    end
  end
end
