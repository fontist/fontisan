# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates the 'post' table per the OpenType spec.
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/post
      class PostCheck < Check
        VALID_VERSIONS = [1.0, 2.0, 2.5, 3.0, 4.0].freeze

        def self.call(font)
          return [] unless font.has_table?("post")

          post = font.table("post")
          head = font.has_table?("head") ? font.table("head") : nil
          issues = []
          issues.concat(validate_version(post))
          issues.concat(validate_italic_angle(post, head))
          issues.concat(validate_is_fixed_pitch(post))
          issues
        end

        def self.code
          :ot_post
        end

        def self.validate_version(post)
          version = post.version.to_f
          return [] if VALID_VERSIONS.include?(version)

          [issue(severity: :error,
                 message: "post.version is #{version} but must be one of " \
                          "#{VALID_VERSIONS.join(', ')}",
                 location: "post.version")]
        end
        private_class_method :validate_version

        def self.validate_italic_angle(post, head)
          angle = post.italic_angle.to_f
          issues = []
          if head&.mac_style
            is_italic = (head.mac_style.to_i & 0x02).positive?
            if is_italic && angle >= 0
              issues << issue(severity: :warning,
                              message: "post.italicAngle is #{angle} but " \
                                       "head.macStyle indicates italic " \
                                       "(angle should be negative)",
                              location: "post.italic_angle")
            elsif !is_italic && angle != 0
              issues << issue(severity: :info,
                              message: "post.italicAngle is #{angle} but " \
                                       "head.macStyle does not indicate italic " \
                                       "(angle should be 0)",
                              location: "post.italic_angle")
            end
          end
          issues
        end
        private_class_method :validate_italic_angle

        def self.validate_is_fixed_pitch(post)
          val = post.is_fixed_pitch.to_i
          return [] if [0, 1].include?(val)

          [issue(severity: :warning,
                 message: "post.isFixedPitch is #{val} but must be 0 " \
                          "(proportional) or 1 (monospace)",
                 location: "post.is_fixed_pitch")]
        end
        private_class_method :validate_is_fixed_pitch
      end
    end
  end
end
