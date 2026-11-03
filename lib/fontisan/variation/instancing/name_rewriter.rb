# frozen_string_literal: true

module Fontisan
  module Variation
    module Instancing
      # Rewrites a name table so it describes one instance of a family.
      class NameRewriter
        Record = Struct.new(:platform, :encoding, :language, :name_id, :text)

        # @param name_data [String] raw name table
        def initialize(name_data)
          @records = parse(name_data)
        end

        def lookup(name_id)
          same = @records.select { |r| r.name_id == name_id }
          rec = same.find { |r| r.platform == 3 && r.language == 0x409 } ||
            same.find { |r| r.platform == 3 } || same.first
          rec&.text
        end

        # Names the instance +label+ (e.g. "Light") of the family.
        def rename(label)
          family = lookup(16) || lookup(1) || "Font"
          legacy = ["Regular", "Bold", "Italic", "Bold Italic"].include?(label)
          full = "#{family} #{label}".strip
          ps = "#{family}-#{label}".delete(" ")
          set(1, legacy ? family : full)
          set(2, legacy ? label : "Regular")
          set(3, "#{lookup(5) || ''};#{ps}".delete_prefix(";"))
          set(4, full)
          set(6, ps)
          set(16, family)
          set(17, label)
          @records.reject! { |r| r.name_id == 25 }
          self
        end

        def to_binary
          recs = @records.sort_by { |r| [r.platform, r.encoding, r.language, r.name_id] }
          strings = +"".b
          entries = recs.map do |r|
            bin = encode(r)
            off = strings.bytesize
            strings << bin
            [r.platform, r.encoding, r.language, r.name_id, bin.bytesize, off]
          end
          header = [0, recs.size, 6 + (recs.size * 12)].pack("nnn")
          header + entries.map { |e| e.pack("n6") }.join + strings
        end

        private

        def set(name_id, text)
          same = @records.select { |r| r.name_id == name_id }
          same.each { |r| r.text = text }
          return if same.any? { |r| r.platform == 3 }

          @records << Record.new(3, 1, 0x409, name_id, text)
        end

        def parse(data)
          count, str_off = data[2, 4].unpack("nn")
          recs = Array.new(count) do |i|
            plat, enc, lang, nid, len, off = data[6 + (i * 12), 12].unpack("n6")
            raw = data[str_off + off, len]
            Record.new(plat, enc, lang, nid, decode(plat, raw))
          end
          recs.reject { |r| r.language >= 0x8000 }
        end

        def decode(platform, raw)
          if [0, 3].include?(platform)
            raw.dup.force_encoding("UTF-16BE").encode("UTF-8", invalid: :replace)
          else
            raw.dup.force_encoding("ISO-8859-1").encode("UTF-8")
          end
        end

        def encode(rec)
          if [0, 3].include?(rec.platform)
            rec.text.encode("UTF-16BE").b
          else
            rec.text.encode("ISO-8859-1", invalid: :replace, undef: :replace).b
          end
        end
      end
    end
  end
end
