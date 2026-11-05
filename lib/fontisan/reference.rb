# frozen_string_literal: true

require "digest"
require "json"

module Fontisan
  # The reference facade: one path-based entry point per engine operation.
  #
  # Every golden is generated through this module and every engine tier
  # (Ruby, native, FFI) serves the same operations, so the signatures, return
  # schemas and error surfaces here are the contract. Operations take a file
  # path, never a loaded font object. They wrap existing classes and add no
  # behaviour except three deliberate additions:
  #
  # 1. An optional `timestamp:` (Unix seconds) reaches the places Ruby stamps
  #    `head.modified` from the clock (WOFF2 encode, and StaticFontBuilder).
  #    nil keeps today's behaviour; operations that do not stamp ignore it.
  # 2. {.subset} copies fontist's `glyph_ids` step (cmap -> uniq -> sort and
  #    its "None of the requested characters exist in <name>" error) before
  #    calling `Subset::Builder` with the web profile.
  # 3. {.convert} runs `Fontisan.convert` quietly (ConvertCommand prints to
  #    stdout otherwise).
  #
  # Read-type results ({.read}, {.audit}, {.audit_dir}, {.scan}) are plain
  # JSON-ready data: Hash with String keys sorted bytewise, Array, String,
  # Integer, true, false, nil. They never contain a Float (Fixed 16.16 values
  # are raw integers) or a clock value. See docs/reference-facade.md or
  # REFERENCE-FACADE.md at the repository root.
  #
  # Errors: operations let the wrapped class's exception propagate unchanged
  # (Errno::ENOENT, Fontisan::InvalidFontError, Fontisan::Error
  # "Conversion failed: ...", ArgumentError for bad options, ...). {.scan}
  # and {.audit_dir} never raise for a bad font; they record the failure in
  # the row.
  module Reference
    FONT_EXTENSIONS = %w[.ttf .otf .ttc .otc .woff .woff2 .dfont .pfa .pfb].freeze

    # Tables whose parsed header fields are included in {.read}.
    SNAPSHOT_TABLES = {
      "head" => :head, "hhea" => :hhea, "maxp" => :maxp, "OS/2" => :os2
    }.freeze

    FIXED_ONE = 65_536

    VARIATION_DIGESTS = {
      "gvar" => :gvar, "HVAR" => :hvar, "VVAR" => :hvar, "MVAR" => :mvar, "STAT" => :stat
    }.freeze

    POST_FIELDS = %i[version_raw italic_angle_raw underline_position underline_thickness
                     is_fixed_pitch min_mem_type42 max_mem_type42 min_mem_type1
                     max_mem_type1].freeze

    autoload :TableDigests, "fontisan/reference/table_digests"

    class << self
      # Read the structure of every face in a font file.
      #
      # @param path [String]
      # @param mode [Symbol] :metadata or :full (FontLoader loading mode)
      # @param lazy [Boolean] FontLoader lazy flag
      # @return [Array<Hash>] one Hash per face (see docs for the schema)
      def read(path, mode: :metadata, lazy: true)
        path = path_arg(path)
        sha = Digest::SHA256.file(path).hexdigest
        format = FontLoader.detect_format(path)&.to_s
        count = face_count(path)
        faces = Array.new(count) do |index|
          font = FontLoader.load(path, font_index: index, mode: mode, lazy: lazy)
          begin
            read_face(font, index, sha, format, mode, lazy)
          ensure
            font.close if font.respond_to?(:close)
          end
        end
        normalize(faces)
      end

      # Per-glyph outline hashes of one face (full mode).
      #
      # glyf fonts: SHA-256 of the glyph's byte range in `glyf`, located by
      # the parsed `loca`. CFF/CFF2 fonts: SHA-256 of the glyph's
      # CharString bytes from the CharStrings INDEX. Empty glyphs hash the
      # empty string.
      #
      # @return [Hash] `{"kind"=>"glyf"|"cff"|nil, "hashes"=>[hex, ...]}`
      def outline_hashes(path, index: 0)
        path = path_arg(path)
        font = FontLoader.load(path, font_index: index, mode: :full,
                                     lazy: true)
        begin
          normalize(outline_data(font))
        ensure
          font.close if font.respond_to?(:close)
        end
      end

      # Structured audit of every face, without clock or version fields.
      #
      # @param path [String]
      # @param validate [Boolean, Symbol] false (no checks), true (default
      #   profile) or a profile name
      # @return [Array<Hash>] one canonical report per face
      def audit(path, validate: false)
        path = path_arg(path)
        result = Commands::AuditCommand.new(
          path, validate: validate || false, include_codepoints: false
        ).run
        normalize(Array(result).map { |report| audit_hash(report) })
      end

      # Audit every font file below a directory.
      #
      # @param dir [String]
      # @param validate [Boolean, Symbol] as for {.audit}
      # @return [Array<Hash>] one entry per file, sorted by relative path:
      #   `{"path"=>rel, "faces"=>[...]}` or `{"path"=>rel, "error"=>{...}}`
      def audit_dir(dir, validate: false)
        dir = path_arg(dir)
        files = font_files(dir)
        entries = files.map do |file|
          rel = file.delete_prefix("#{dir}/")
          begin
            { path: rel, faces: audit(file, validate: validate) }
          rescue StandardError => e
            { path: rel, error: { class: e.class.name, message: e.message } }
          end
        end
        normalize(entries)
      end

      # One row per font face for every path (see {Fontisan::Scan}).
      #
      # @param paths [Array<String>]
      # @return [Array<Hash>] rows in input order; never raises for a bad font
      def scan(paths)
        paths = Array(paths).map { |p| path_arg(p, must_exist: false) }
        normalize(Scan.call(paths))
      end

      # Convert a font file to another format.
      #
      # @param path [String]
      # @param to [Symbol, String] target format (:ttf, :otf, :woff, :woff2,
      #   :ttc, ...); a single format
      # @param output [String] output path
      # @param timestamp [Integer, Time, nil] fixed head.modified for WOFF2
      #   output; ignored for other targets
      # @return [Hash] the ConvertCommand result (success, input_path,
      #   output_path, source_format, target_format, input_size, output_size,
      #   variation_strategy | num_fonts)
      # @raise [Fontisan::Error] "Conversion failed: ..."
      def convert(path, output:, timestamp: nil, **options)
        path = path_arg(path)
        target = options.fetch(:to)
        opts = { quiet: true, **options.except(:to) }
        opts[:timestamp] = unix_seconds(timestamp) if stamps?(target, timestamp)
        Fontisan.convert(path, to: target, output: output, **opts)
      end

      # Extract one member of a collection as a standalone font.
      #
      # @return [String] path of the extracted file (as UnpackCommand reports)
      def extract(path, index:, output_dir:)
        path = path_arg(path)
        Commands::UnpackCommand.new(
          path, output_dir: output_dir, font_index: index
        ).run[:extracted_files].first
      end

      # Static instance of a variable font.
      #
      # @param coords [Hash{String=>Numeric}] axis tag => value
      # @param timestamp [Integer, Time, nil] accepted for uniformity;
      #   Instancer does not stamp, so it is ignored
      # @return [String] binary font bytes
      def instance(path, coords:, timestamp: nil)
        _ = timestamp
        font = FontLoader.load(path_arg(path), mode: :full, lazy: false)
        values = coords.to_h { |tag, value| [tag.to_s, Float(value)] }
        Variable::Instancer.new(font).instance(values)
      end

      # Glyph ids kept by a subset request (fontist's `glyph_ids`).
      #
      # @param unicodes [Array<Integer>, nil] codepoints
      # @param text [String, nil] characters to keep
      # @return [Array<Integer>] sorted, unique glyph ids
      # @raise [Fontisan::Error] "None of the requested characters exist in
      #   <basename>"
      def glyph_ids(path, unicodes: nil, text: nil)
        path = path_arg(path)
        font = FontLoader.load(path, mode: :full, lazy: false)
        codepoints = Array(unicodes).map(&:to_i) + text.to_s.codepoints
        gids_for(font, codepoints, File.basename(path))
      end

      # Subset a font to the glyphs of the given characters.
      #
      # @param profile [String] subset profile (default "web")
      # @param timestamp [Integer, Time, nil] ignored: Subset::Builder keeps
      #   the source head.modified
      # @return [String] binary font bytes
      def subset(path, unicodes: nil, text: nil, profile: "web", timestamp: nil)
        _ = timestamp
        path = path_arg(path)
        font = FontLoader.load(path, mode: :full, lazy: false)
        codepoints = Array(unicodes).map(&:to_i) + text.to_s.codepoints
        gids = gids_for(font, codepoints, File.basename(path))
        options = Subset::Options.new(profile: profile)
        Subset::Builder.new(font, gids, options).build
      end

      # Canonical JSON text of a read-type result: sorted keys, two-space
      # indent, trailing newline.
      def canonical_json(data)
        "#{JSON.pretty_generate(normalize(data))}\n"
      end

      # Recursively convert to JSON-ready data with sorted String keys.
      # Floats are rejected: Fixed values must be stored as raw integers.
      def normalize(value)
        case value
        when Hash
          value.map { |k, v| [k.to_s, normalize(v)] }.sort_by(&:first).to_h
        when Array then value.map { |v| normalize(v) }
        when Symbol then value.to_s
        when BinData::Base then normalize(value.snapshot)
        when Float
          raise ArgumentError, "Float #{value} in canonical output"
        else value
        end
      end

      private

      def path_arg(path, must_exist: true)
        unless path.is_a?(String) || path.respond_to?(:to_path)
          raise TypeError,
                "Reference operations take a file path, got #{path.class}"
        end

        path = File.path(path)
        raise Errno::ENOENT, path if must_exist && !File.exist?(path)

        path
      end

      def face_count(path)
        FontLoader.collection?(path) ? FontLoader.load_collection(path).num_fonts : 1
      end

      def font_files(dir)
        Dir.glob(File.join(dir, "**", "*"))
          .select { |f| File.file?(f) && FONT_EXTENSIONS.include?(File.extname(f).downcase) }
          .sort
      end

      def stamps?(target, timestamp)
        !timestamp.nil? && target.to_s == "woff2"
      end

      def unix_seconds(timestamp)
        timestamp.respond_to?(:to_time) ? timestamp.to_time.to_i : Integer(timestamp)
      end

      def gids_for(font, codepoints, name)
        mappings = font.table("cmap").unicode_mappings
        gids = codepoints.uniq.filter_map { |cp| mappings[cp] }.uniq.sort
        return gids if gids.any?

        raise Fontisan::Error, "None of the requested characters exist in #{name}"
      end

      # ---- audit ---------------------------------------------------------

      def audit_hash(report)
        data = JSON.parse(report.to_json)
        data.delete("generated_at")
        data.delete("fontisan_version")
        data["font_revision_raw"] = fixed_raw(data.delete("font_revision"))
        data["axes"] = Array(data["axes"]).map { |axis| axis_raw(axis) }
        data
      end

      def axis_raw(axis)
        %w[min_value default_value max_value].each_with_object(axis) do |key, h|
          h["#{key}_raw"] = fixed_raw(h.delete(key))
        end
      end

      def fixed_raw(value)
        value.nil? ? nil : (value * FIXED_ONE).round
      end

      # ---- read ----------------------------------------------------------

      def read_face(font, index, sha, format, mode, lazy)
        {
          index: index,
          format: format,
          mode: mode.to_s,
          lazy: lazy ? true : false,
          file_sha256: sha,
          tables: table_digests(font),
          names: name_records(font),
          header_fields: header_fields(font),
          cmap: cmap_digest(font),
          fvar: fvar_data(font),
          outlines: outline_summary(font),
          post: post_data(font),
          layout: layout_data(font),
          variation: variation_data(font),
        }
      end

      # post header fields plus a count and digest of the glyph names (names
      # joined with "\n"); a failure to read the names is recorded, not raised.
      def post_data(font)
        table = available_table(font, "post")
        return nil unless table

        data = POST_FIELDS.to_h { |f| [f, table.public_send(f).to_i] }
        begin
          names = table.glyph_names
          data[:glyph_name_count] = names.size
          data[:glyph_names_sha256] = Digest::SHA256.hexdigest(names.join("\n"))
        rescue StandardError => e
          data[:glyph_names_error] = e.class.name
        end
        data
      end

      # GSUB/GPOS script tags and, per script, feature tags, as the table
      # classes report them (they swallow parse errors and answer []).
      def layout_data(font)
        %w[GSUB GPOS].to_h do |tag|
          table = available_table(font, tag)
          next [tag, nil] unless table

          scripts = table.scripts
          [tag, {
            scripts: scripts,
            features: scripts.to_h { |s| [s, table.features(script_tag: s)] },
          }]
        end
      end

      # Parsed digests of the variation tables, from the raw table bytes
      # (see {TableDigests}). A table that cannot be read records the error.
      def variation_data(font)
        VARIATION_DIGESTS.to_h do |tag, digest|
          [tag, digest_table(font, tag, digest)]
        end
      end

      def digest_table(font, tag, digest)
        return nil unless font.has_table?(tag)

        font.table(tag)
        raw = raw_table(font, tag)
        raw ? TableDigests.public_send(digest, raw) : nil
      rescue ArgumentError
        nil
      rescue StandardError => e
        { error: e.class.name }
      end

      # Digest of every table the loading mode makes available. A table that
      # the mode gates out has a nil digest; a table that fails to load or
      # parse records the error class (Ruby fails lazily, on first access).
      def table_digests(font)
        font.table_names.map do |tag|
          entry = { tag: tag, length: nil, sha256: nil, error: nil }
          begin
            font.table(tag)
            raw = raw_table(font, tag)
            if raw
              entry[:length] = raw.bytesize
              entry[:sha256] = Digest::SHA256.hexdigest(raw)
            end
          rescue ArgumentError
            entry[:error] = nil # gated by the loading mode
          rescue StandardError => e
            entry[:error] = e.class.name
          end
          entry
        end
      end

      def raw_table(font, tag)
        if font.method(:table_data).arity.zero?
          font.table_data[tag]
        else
          font.table_data(tag)
        end
      end

      def name_records(font)
        table = available_table(font, "name")
        return [] unless table

        table.name_records.map do |record|
          {
            platform_id: record.platform_id.to_i,
            encoding_id: record.encoding_id.to_i,
            language_id: record.language_id.to_i,
            name_id: record.name_id.to_i,
            string: decode_name(table, record),
          }
        end
      end

      # Same decoding rules as fontist's decode_name_record_manually.
      def decode_name(table, record)
        storage = table.string_storage.to_s.b
        length = record.string_length
        return nil if record.string_offset + length > storage.bytesize || length.zero?

        data = storage.byteslice(record.string_offset, length)
        case record.platform_id.to_i
        when 0, 3
          data.dup.force_encoding("UTF-16BE")
            .encode("UTF-8", invalid: :replace, undef: :replace)
        when 1
          data.dup.force_encoding("ASCII-8BIT")
            .encode("UTF-8", invalid: :replace, undef: :replace)
        else
          data.dup.force_encoding("UTF-8").scrub
        end
      end

      def header_fields(font)
        SNAPSHOT_TABLES.keys.each_with_object({}) do |tag, out|
          table = available_table(font, tag)
          out[tag] = table ? snapshot(table) : nil
        end
      end

      def snapshot(table)
        table.snapshot.transform_values { |v| snapshot_value(v) }
      end

      # Strings that are printable ASCII (tags, vendor ids) stay text; any
      # other String is "0x" + hex.
      def snapshot_value(value)
        case value
        when String
          value.b.match?(/\A[\x20-\x7e]*\z/n) ? value : "0x#{value.b.unpack1('H*')}"
        when Array then value.map { |v| snapshot_value(v) }
        when Hash then value.transform_values { |v| snapshot_value(v) }
        else value
        end
      end

      # Count and digest of the sorted codepoints: SHA-256 over each
      # codepoint as a big-endian uint32, ascending.
      def cmap_digest(font)
        table = available_table(font, "cmap")
        return nil unless table

        codepoints = (table.unicode_mappings || {}).keys.sort
        {
          count: codepoints.size,
          sha256: Digest::SHA256.hexdigest(codepoints.pack("N*")),
          subtable_formats: table.subtable_formats,
        }
      end

      def fvar_data(font)
        table = available_table(font, "fvar")
        return nil unless table

        {
          axes: table.axes.map { |axis| snapshot(axis) },
          instances: table.instances.compact.map { |inst| instance_data(inst) },
        }
      end

      def instance_data(inst)
        {
          name_id: inst[:name_id],
          flags: inst[:flags],
          postscript_name_id: inst[:postscript_name_id],
          coordinates_raw: Array(inst[:coordinates]).map { |c| (c * FIXED_ONE).round },
        }
      end

      def outline_summary(font)
        data = outline_data(font)
        return { kind: nil, count: 0, digest: nil } if data[:kind].nil?

        hashes = data[:hashes]
        {
          kind: data[:kind],
          count: hashes.size,
          digest: Digest::SHA256.hexdigest(hashes.map { |h| [h].pack("H*") }.join),
        }
      rescue StandardError => e
        { kind: nil, count: 0, digest: nil, error: e.class.name }
      end

      def outline_data(font)
        if available_table(font, "glyf") && available_table(font, "loca")
          { kind: "glyf", hashes: glyf_hashes(font) }
        elsif (cff = cff_table(font))
          { kind: "cff", hashes: cff_hashes(cff) }
        elsif font.has_table?("CFF2") && (raw = raw_table(font, "CFF2"))
          { kind: "cff2", hashes: TableDigests.cff2_charstrings(raw).map { |c| Digest::SHA256.hexdigest(c) } }
        else
          { kind: nil, hashes: [] }
        end
      end

      def glyf_hashes(font)
        glyf = raw_table(font, "glyf")
        loca = font.table("loca")
        head = font.table("head")
        maxp = font.table("maxp")
        loca.parse_with_context(head.index_to_loc_format, maxp.num_glyphs) unless loca.parsed?
        Array.new(maxp.num_glyphs) do |gid|
          bytes = glyf.byteslice(loca.offset_for(gid), loca.size_of(gid)) || ""
          Digest::SHA256.hexdigest(bytes)
        end
      end

      # WoffFont#table returns nil for "CFF " (measured), so parse the raw
      # table when the font class gives no parsed one.
      def cff_table(font)
        parsed = available_table(font, "CFF ")
        return parsed if parsed

        raw = font.has_table?("CFF ") && raw_table(font, "CFF ")
        raw ? Tables::Cff.read(raw) : nil
      end

      def cff_hashes(cff)
        index = cff.charstrings_index
        return [] unless index

        Array.new(index.count) { |gid| Digest::SHA256.hexdigest(index[gid]) }
      end

      # The parsed table, or nil when the font lacks it or the loading mode
      # gates it out.
      def available_table(font, tag)
        return nil unless font.has_table?(tag)

        font.table(tag)
      rescue ArgumentError
        nil
      end
    end
  end
end
