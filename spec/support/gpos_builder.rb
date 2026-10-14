# frozen_string_literal: true

module GposBuilder
  def gpos_coverage(glyphs, format: 1)
    return [1, glyphs.size, *glyphs].pack("n*") if format == 1

    [2, glyphs.size, *glyphs.each_with_index.flat_map { |gid, i| [gid, gid, i] }].pack("n*")
  end

  def gpos_class_def(classes, format: 2)
    if format == 1
      start = classes.keys.min || 0
      finish = classes.keys.max || (start - 1)
      values = (start..finish).map { |gid| classes.fetch(gid, 0) }
      [1, start, values.size, *values].pack("n*")
    else
      [2, classes.size, *classes.sort.flat_map { |gid, value| [gid, gid, value] }].pack("n*")
    end
  end

  def gpos_value(value, format)
    (0...8).filter_map do |bit|
      next if (format & (1 << bit)).zero?

      bit == 2 ? value : bit + 10
    end.pack("n*")
  end

  def gpos_pair_one(pairs, coverage_format: 1, value_format: 4, second_format: 0)
    glyphs = pairs.keys.sort
    coverage = gpos_coverage(glyphs, format: coverage_format)
    base = 10 + glyphs.size * 2
    cursor = base + coverage.bytesize
    sets = glyphs.map do |gid|
      [pairs[gid].size].pack("n") + pairs[gid].sort.map do |right, value|
        [right].pack("n") + gpos_value(value, value_format) + gpos_value(987, second_format)
      end.join
    end
    offsets = sets.map do |data|
      offset = cursor
      cursor += data.bytesize
      offset
    end
    [1, base, value_format, second_format, glyphs.size, *offsets].pack("n*") + coverage + sets.join
  end

  def gpos_pair_two(coverage: [2], first: { 2 => 1 }, second: { 3 => 1 },
                    matrix: [[0, 0], [-11, -29]], coverage_format: 1,
                    class_format: 2, value_format: 4, second_format: 0)
    records = matrix.flatten.map do |value|
      gpos_value(value, value_format) + gpos_value(123, second_format)
    end.join
    coverage_data = gpos_coverage(coverage, format: coverage_format)
    first_data = gpos_class_def(first, format: class_format)
    second_data = gpos_class_def(second, format: class_format)
    offset = 16 + records.bytesize
    [2, offset, value_format, second_format, offset + coverage_data.bytesize,
     offset + coverage_data.bytesize + first_data.bytesize,
     matrix.size, matrix.first.size].pack("n*") + records + coverage_data + first_data + second_data
  end

  def gpos_lookup(subtables, type: 2, flags: 0)
    cursor = 6 + subtables.size * 2 + ((flags & 16).zero? ? 0 : 2)
    offsets = subtables.map do |data|
      offset = cursor
      cursor += data.bytesize
      offset
    end
    [type, flags, subtables.size, *offsets].pack("n*") +
      ((flags & 16).zero? ? "" : [0].pack("n")) + subtables.join
  end

  def gpos_binary(lookups, script_tag: "latn", feature_tag: "kern", indices: nil,
                  required: false, default: true, language_feature: false)
    indices ||= (0...lookups.size).to_a
    langsys = [0, required ? 0 : 0xffff, required ? 0 : 1, *(required ? [] : [0])].pack("n*")
    script_header = [default ? 4 : 0, 0].pack("n*")
    if language_feature
      script_header = "#{[default ? 10 : 0, 1].pack('n*')}TRK #{[10 + (default ? langsys.bytesize : 0)].pack('n')}"
    end
    script = script_header + (default ? langsys : "") + (language_feature ? langsys : "")
    script_list = "#{[1].pack('n')}#{script_tag}#{[8].pack('n')}#{script}"
    feature_list = [1].pack("n") + feature_tag + [8, 0, indices.size, *indices].pack("n*")
    cursor = 2 + lookups.size * 2
    offsets = lookups.map do |lookup|
      offset = cursor
      cursor += lookup.bytesize
      offset
    end
    lookup_list = [lookups.size, *offsets].pack("n*") + lookups.join
    [1, 0, 10, 10 + script_list.bytesize,
     10 + script_list.bytesize + feature_list.bytesize].pack("n*") + script_list + feature_list + lookup_list
  end
end
