# frozen_string_literal: true

require "digest"

module Fontisan
  # Builds the scan rows served by {Fontisan::Reference.scan}: one row per font
  # face, carrying everything fontist's `FontFile`, `CollectionFile` and
  # indexability check read from a font, so the same rows can be produced by
  # any engine tier.
  #
  # The field set and the name-decoding rules are taken from fontist at
  # 85e904c96fff60f60781ae0eb11a8c06e0c73816 (`lib/fontist/font_file.rb`,
  # `collection_file.rb`). This class never raises for a bad font: the failure
  # that fontist would raise or show is recorded in the row's `errors`.
  #
  # Rows are plain Hashes with Symbol keys (see docs/reference-facade.md for
  # the schema). Every call builds its own state, so concurrent calls on
  # different paths are safe.
  class Scan
    NAME_FIELDS = {
      full_name: Tables::Name::FULL_NAME,
      family_name: Tables::Name::FAMILY,
      subfamily_name: Tables::Name::SUBFAMILY,
      preferred_family: Tables::Name::PREFERRED_FAMILY,
      preferred_subfamily: Tables::Name::PREFERRED_SUBFAMILY,
      postscript_name: Tables::Name::POSTSCRIPT_NAME,
    }.freeze

    RIBBI = ["regular", "bold", "italic", "bold italic"].freeze

    FONT_FILE_ERROR = "Fontist::Errors::FontFileError"
    INDEXABILITY_ERROR = "Fontist::Errors::FontIndexabilityValidationError"
    NOT_A_COLLECTION = {
      class: FONT_FILE_ERROR,
      message: "File is not a recognized font collection (TTC/OTC/dfont)",
      cause: nil,
    }.freeze

    # @param paths [Array<String>] font file paths
    # @return [Array<Hash>] rows in input order, faces in index order
    def self.call(paths)
      Array(paths).flat_map { |path| new(path).rows }
    end

    # @param path [String]
    def initialize(path)
      @path = path.to_s
    end

    # @return [Array<Hash>] one row per face; one row with
    #   `collection_index: nil` when no face could be enumerated
    def rows
      facts = file_facts
      return [failed_file_row(facts)] if facts[:fatal]

      if facts[:is_collection]
        collection_rows(facts)
      else
        [face_row(facts, nil, 1)]
      end
    end

    private

    # ---- file level -----------------------------------------------------

    # What FontFile reads first: collection?, detect_format, sha256.
    def file_facts
      facts = { sha256: nil, format: nil, is_collection: false, fatal: nil }
      facts[:sha256] = Digest::SHA256.file(@path).hexdigest
      facts[:is_collection] = FontLoader.collection?(@path)
      facts[:format] = detect_format
      facts
    rescue StandardError => e
      facts[:fatal] = e
      facts
    end

    def detect_format
      format = FontLoader.detect_format(@path)
      format&.to_s
    rescue StandardError
      nil
    end

    def failed_file_row(facts)
      error = facts[:fatal]
      row = base_row(facts, nil, 0)
      row[:errors][:font_file] = font_file_error(error)
      row[:errors][:collection_file] = load_error(error)
      row
    end

    # ---- collections ----------------------------------------------------

    def collection_rows(facts)
      collection = begin
        FontLoader.load_collection(@path)
      rescue StandardError => e
        e
      end

      if collection.is_a?(StandardError)
        row = base_row(facts, nil, 0)
        row[:errors][:font_file] = font_file_error(collection)
        row[:errors][:collection_file] = load_error(collection)
        return [row]
      end

      count = collection.num_fonts
      Array.new(count) { |index| face_row(facts, index, count) }
    end

    # ---- one face -------------------------------------------------------

    def face_row(facts, index, num_faces)
      row = base_row(facts, index, num_faces)
      fontist_face = index.nil? || index.zero?

      meta = load_face(index, lazy: true)
      if meta.is_a?(StandardError)
        row[:errors][:font_file] = font_file_error(meta) if fontist_face
      else
        begin
          fill_from_face(row, meta, index)
        rescue StandardError => e
          row[:errors][:font_file] = font_file_error(e) if fontist_face
        ensure
          meta.close if meta.respond_to?(:close)
        end
      end

      if index.nil?
        row[:errors][:collection_file] = NOT_A_COLLECTION
      else
        fill_collection_errors(row, index)
      end
      row
    end

    # FontFile flow: validate -> names (with fallback) -> fvar -> instances.
    def fill_from_face(row, font, index)
      row[:validation] = validate(font)
      row[:names] = names_with_fallback(font)
      row[:has_fvar] = font.has_table?("fvar")
      row[:variable_instances] = variable_instances(index) if row[:has_fvar] && row[:names][:family_name]
    end

    # CollectionFile flow: metadata, lazy: false, english names only; and the
    # indexability check of the first face, which gates build_collection for
    # the whole file (so every row of the file carries the same value).
    def fill_collection_errors(row, index)
      member = load_face(index, lazy: false)
      if member.is_a?(StandardError)
        row[:errors][:collection_member] = error_info(member)
      else
        begin
          row[:english_names] = english_names(member)
        rescue StandardError => e
          row[:errors][:collection_member] = error_info(e)
        ensure
          member.close if member.respond_to?(:close)
        end
      end
      row[:errors][:collection_file] = first_face_error
    end

    def first_face_error
      return @first_face_error if defined?(@first_face_error)

      @first_face_error = compute_first_face_error
    end

    def compute_first_face_error
      first = load_face(0, lazy: true)
      return load_error(first) if first.is_a?(StandardError)

      begin
        report = validate(first)
        report[:valid] ? nil : indexability_error(report)
      rescue StandardError => e
        load_error(e)
      ensure
        first.close if first.respond_to?(:close)
      end
    end

    def indexability_error(report)
      { class: INDEXABILITY_ERROR,
        message: "Font collection failed indexability validation " \
                 "(first font): #{report[:error_summary]}",
        cause: nil }
    end

    # CollectionFile wraps every non-indexability failure this way.
    def load_error(error)
      wrapped("Font collection could not be loaded: #{error.message}",
              FONT_FILE_ERROR, error)
    end

    def load_face(index, lazy:)
      args = { mode: :metadata, lazy: lazy }
      args[:font_index] = index unless index.nil?
      FontLoader.load(@path, **args)
    rescue StandardError => e
      e
    end

    # ---- names ----------------------------------------------------------

    def names_with_fallback(font)
      name_table = font.table(Constants::NAME_TAG)
      return {} unless name_table

      NAME_FIELDS.transform_values do |id|
        name_table.english_name(id) || any_name(name_table, id)
      end
    end

    def english_names(font)
      name_table = font.table(Constants::NAME_TAG)
      return {} unless name_table

      NAME_FIELDS.transform_values { |id| name_table.english_name(id) }
    end

    # fontist's extract_any_name / decode_name_record_manually.
    def any_name(name_table, name_id)
      records = name_table.name_records.select { |r| r.name_id == name_id }
      records.each do |record|
        decoded = decode_record(name_table, record)
        return decoded unless decoded.nil? || decoded.empty?
      end
      nil
    end

    def decode_record(name_table, record)
      storage = name_table.string_storage.to_s.b
      offset = record.string_offset
      length = record.string_length
      return nil if offset + length > storage.bytesize || length.zero?

      data = storage.byteslice(offset, length)
      case record.platform_id
      when 0, 3
        data.dup.force_encoding("UTF-16BE")
          .encode("UTF-8", invalid: :replace, undef: :replace)
      when 1
        data.dup.force_encoding("ASCII-8BIT")
          .encode("UTF-8", invalid: :replace, undef: :replace)
      else
        data.dup.force_encoding("UTF-8")
      end
    end

    # ---- variable instances (fontist FontFile.extract_variable_instances) -

    # fvar data is gated out of metadata mode, so this is the second load.
    def variable_instances(index)
      font = if index.nil?
               FontLoader.load(@path, mode: :full, lazy: true)
             else
               FontLoader.load(@path, font_index: index, mode: :full, lazy: true)
             end
      instances_of(font)
    rescue StandardError
      []
    ensure
      font.close if font.respond_to?(:close)
    end

    def instances_of(font)
      return [] unless font.has_table?("fvar")

      fvar = font.table("fvar")
      name_table = font.table(Constants::NAME_TAG)
      return [] unless name_table

      base = name_table.english_name(Tables::Name::PREFERRED_FAMILY) ||
        any_name(name_table, Tables::Name::PREFERRED_FAMILY) ||
        name_table.english_name(Tables::Name::FAMILY)
      return [] unless base

      fvar.instances.filter_map do |instance|
        style = name_table.english_name(instance[:name_id]) ||
          any_name(name_table, instance[:name_id])
        next unless style

        instance_entry(base, style)
      end
    rescue StandardError
      []
    end

    def instance_entry(base, style)
      if RIBBI.include?(style.downcase)
        { family: base, style: style, full_name: "#{base} #{style}" }
      else
        family = "#{base} #{style}"
        { family: family, style: "Regular", full_name: family }
      end
    end

    # ---- validation -----------------------------------------------------

    # The raw indexability result, with fontist's joined message string.
    def validate(font)
      report = Validators::ProfileLoader.load(:indexability).validate(font)
      errors = report.errors
      {
        profile: "indexability",
        valid: report.valid? || false,
        status: report.status,
        issues: report.issues.map do |i|
          { severity: i.severity, category: i.category, message: i.message,
            location: i.location }
        end,
        error_summary: errors.map { |e| "#{e.category}: #{e.message}" }.join("; "),
      }
    end

    # ---- rows and errors ------------------------------------------------

    def base_row(facts, index, num_faces)
      {
        path: @path,
        collection_index: index,
        sha256: facts[:sha256],
        format: facts[:format],
        is_collection: facts[:is_collection],
        num_faces: num_faces,
        has_fvar: false,
        names: nil,
        english_names: nil,
        variable_instances: [],
        validation: nil,
        errors: { font_file: nil, collection_file: nil, collection_member: nil },
      }
    end

    # `FontFile.raise_font_file_error`: "Font file could not be parsed: <inspect>."
    def font_file_error(error)
      wrapped("Font file could not be parsed: #{error.inspect}.",
              FONT_FILE_ERROR, error)
    end

    def wrapped(message, klass, cause)
      { class: klass, message: message, cause: error_info(cause) }
    end

    def error_info(error)
      { class: error.class.name, message: error.message }
    end
  end
end
