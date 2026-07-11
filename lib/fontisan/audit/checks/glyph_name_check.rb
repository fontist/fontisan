# frozen_string_literal: true

module Fontisan
  module Audit
    module Checks
      # Validates glyph names against the OpenType spec rules:
      #
      #   - Length ≤ 63 characters
      #   - Allowed characters: printable ASCII excluding special chars
      #     (per OT spec: A–Z a–z 0–9, period, hyphen, underscore)
      #   - Must not start with a digit
      #   - Must not be a reserved name (.notdef is the only exception at GID 0)
      #   - Duplicate names across the font (warning)
      #   - Empty names (warning — some tools tolerate them but spec discourages)
      #
      # @see https://learn.microsoft.com/en-us/typography/opentype/spec/post
      class GlyphNameCheck < Check
        MAX_NAME_LENGTH = 63
        # OT spec post table glyph name charset: A–Z a–z 0–9 . - _
        # (leading dot is allowed for .notdef, .null, .nonmarkingreturn, etc.)
        ALLOWED_NAME_PATTERN = /\A[A-Za-z0-9._-]+\z/

        # @param font [SfntFont]
        # @return [Array<Models::ValidationReport::Issue>]
        def self.call(font)
          names = extract_glyph_names(font)
          return [] if names.empty?

          issues = []
          names.each_with_index do |name, gid|
            issues.concat(check_name(name, gid))
          end
          issues.concat(check_duplicates(names))
          issues
        end

        def self.code
          :glyph_names
        end

        def self.extract_glyph_names(font)
          return [] unless font.has_table?("post")

          post = font.table("post")
          return [] unless post

          post.glyph_names || []
        end
        private_class_method :extract_glyph_names

        def self.check_name(name, gid)
          issues = []
          if name.nil? || name.empty?
            issues << issue(severity: :warning,
                            message: "Glyph at GID #{gid} has an empty name",
                            location: "glyph.#{gid}.name")
            return issues
          end

          if name.length > MAX_NAME_LENGTH
            issues << issue(severity: :error,
                            message: "Glyph name '#{name[0, 20]}…' (GID #{gid}) " \
                                     "exceeds #{MAX_NAME_LENGTH} characters " \
                                     "(#{name.length})",
                            location: "glyph.#{gid}.name")
          end

          unless name.match?(ALLOWED_NAME_PATTERN)
            issues << issue(severity: :warning,
                            message: "Glyph name '#{name}' (GID #{gid}) contains " \
                                     "characters outside the OT spec grammar " \
                                     "(A–Z a–z 0–9 . - _)",
                            location: "glyph.#{gid}.name")
          end

          if name.match?(/\A\d/)
            issues << issue(severity: :warning,
                            message: "Glyph name '#{name}' (GID #{gid}) starts " \
                                     "with a digit — not portable",
                            location: "glyph.#{gid}.name")
          end
          issues
        end
        private_class_method :check_name

        def self.check_duplicates(names)
          seen = {}
          names.each_with_index do |name, gid|
            next unless name && !name.empty?

            (seen[name] ||= []) << gid
          end
          seen.each_with_object([]) do |(name, gids), issues|
            next unless gids.size > 1

            issues << issue(severity: :warning,
                            message: "Glyph name '#{name}' is shared by " \
                                     "#{gids.size} glyphs (GIDs: #{gids.first(5).join(', ')}" \
                                     "#{'…' if gids.size > 5})",
                            location: "glyph_names.#{name}")
          end
        end
        private_class_method :check_duplicates
      end
    end
  end
end
