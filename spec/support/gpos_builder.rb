# frozen_string_literal: true

require "objspace"
require "open3"
require "rbconfig"

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

  def gpos_lookup_alias_binary(count:, glyphs: 4096)
    subtable = gpos_pair_two(coverage: [0], first: {}, second: {}, matrix: [[-1]], coverage_format: 2)
    coverage = subtable.byteslice(2, 2).unpack1("n")
    subtable[coverage + 6, 2] = [glyphs - 1].pack("n")
    lookup = gpos_lookup([subtable])
    data = gpos_binary([lookup] * count)
    list_offset = data.byteslice(8, 2).unpack1("n")
    data.byteslice(0, list_offset) + [count, *Array.new(count, 2 + count * 2)].pack("n*") + lookup
  end

  def gpos_lookup_subtable_alias_binary(count:, repetitions:, subtables:)
    cursor = 6 + 2 * repetitions * subtables.size
    offsets = subtables.map do |data|
      offset = cursor
      cursor += data.bytesize
      offset
    end
    entries = Array.new(repetitions, offsets).flatten
    lookup = [2, 0, entries.size, *entries].pack("n*") + subtables.join
    data = gpos_binary([lookup] * count)
    base = data.byteslice(8, 2).unpack1("n")
    data.byteslice(0, base) + [count, *Array.new(count, 2 + count * 2)].pack("n*") + lookup
  end

  def gpos_subtable_decode_counts(data)
    base = data.byteslice(8, 2).unpack1("n")
    lookup_offset = base + data.byteslice(base + 2, 2).unpack1("n")
    view_class = Fontisan::Tables::Gpos.const_get(:BinaryView)
    reads = 0
    trace = TracePoint.new(:call) do |event|
      next unless event.method_id == :array && event.self.is_a?(view_class)
      next unless event.self.instance_variable_get(:@offset) == lookup_offset

      reads += 1 if event.binding.local_variable_get(:offset) == 6
    end
    table = Fontisan::Tables::Gpos.read(data)
    pairs = nil
    trace.enable { pairs = table.kern_pairs }
    [pairs, reads]
  end

  def gpos_pair_set_alias_binary(count:, rights: 4096)
    records = (0...rights).map { |gid| [gid, -1].pack("n*") }.join
    coverage = [2, 1, 0, count - 1, 0].pack("n*")
    base = 10 + count * 2
    offsets = Array.new(count, base + coverage.bytesize)
    subtable = [1, base, 4, 0, count, *offsets].pack("n*") + coverage + [rights].pack("n") + records
    gpos_binary([gpos_lookup([subtable])])
  end

  def gpos_shared_coverage_binary(count:, glyphs: 4096)
    lookup = gpos_lookup([gpos_pair_two(coverage: [0], first: {}, second: {}, matrix: [[-1]])])
    data = gpos_binary([lookup] * count)
    list_offset = data.byteslice(8, 2).unpack1("n")
    header_size = 2 + count * 2
    positions_base = header_size + count * 8
    coverage_base = positions_base + count * 18
    class_base = coverage_base + 10
    lookup_offsets = (0...count).map { |index| header_size + index * 8 }
    headers = (0...count).map do |index|
      [2, 0, 1, positions_base + index * 18 - lookup_offsets[index]].pack("n*")
    end.join
    positions = (0...count).map do |index|
      base = positions_base + index * 18
      [2, coverage_base - base, 4, 0, class_base - base, class_base + 4 - base, 1, 1, -1].pack("n*")
    end.join
    list = [count, *lookup_offsets].pack("n*") + headers + positions +
      [2, 1, 0, glyphs - 1, 0, 2, 0, 2, 0].pack("n*")
    data.byteslice(0, list_offset) + list
  end

  def gpos_measured_pairs(data, glyph_count:)
    was_disabled = GC.disable
    arrays_before = ObjectSpace.memsize_of_all(Array)
    before = GC.stat(:total_allocated_objects)
    pairs = Fontisan::Tables::Gpos.read(data).kern_pairs(glyph_count: glyph_count)
    [pairs, GC.stat(:total_allocated_objects) - before,
     ObjectSpace.memsize_of_all(Array) - arrays_before]
  ensure
    GC.enable unless was_disabled
  end

  def gpos_measured_first(pairs)
    was_disabled = GC.disable
    before = ObjectSpace.memsize_of_all(Array)
    first = pairs.each.first
    [first, ObjectSpace.memsize_of_all(Array) - before]
  ensure
    GC.enable unless was_disabled
  end

  def gpos_shared_pair_set_binary(first_formats: [4, 1], second_formats: [0, 0], records: [1, 3, -29])
    data = gpos_binary([gpos_lookup(["ignored"])] * 2)
    list_offset = data.byteslice(8, 2).unpack1("n")
    positions_base = 22
    coverage_base = 46
    pair_base = 52
    headers = [2, 0, 1, 16, 2, 0, 1, 20].pack("n*")
    positions = (0...2).map do |index|
      base = positions_base + index * 12
      [1, coverage_base - base, first_formats[index], second_formats[index], 1, pair_base - base].pack("n*")
    end.join
    list = [2, 6, 14].pack("n*") + headers + positions + [1, 1, 2, *records].pack("n*")
    data.byteslice(0, list_offset) + list
  end

  def gpos_feature_alias_binary(count: 32, indices: 1000)
    langsys = [0, 0xffff, count, *(0...count)].pack("n*")
    scripts = "#{[1].pack('n')}latn#{[8, 4, 0].pack('n*')}#{langsys}"
    feature_records = Array.new(count) { "kern#{[2 + count * 6].pack('n')}" }.join
    features = [count].pack("n") + feature_records + [0, indices, *Array.new(indices, 0)].pack("n*")
    lookup = gpos_lookup([gpos_pair_two(coverage: [0], first: {}, second: {}, matrix: [[-1]])])
    lookups = [1, 4].pack("n*") + lookup
    [1, 0, 10, 10 + scripts.bytesize, 10 + scripts.bytesize + features.bytesize].pack("n*") +
      scripts + features + lookups
  end

  def gpos_valid_overlapping_features_binary(count: 32, indices: 5000, nested: false)
    lookup_count = indices + 1
    scripts = "#{[1].pack('n')}latn#{[8, 4, 0, 0, 0xffff, count, *(0...count)].pack('n*')}"
    header = 2 + count * 6
    records = (0...count).map { |index| "kern#{[header + index * 4].pack('n')}" }.join
    counts = (0...count).map { |index| nested && index.odd? ? 1 : indices }
    features = [count].pack("n") + records + counts.map { |size| [0, size].pack("n*") }.join +
      "\x00".b * (indices * 2)
    lookup = gpos_lookup([gpos_pair_two(coverage: [0], first: {}, second: {}, matrix: [[-1]])])
    data = "\x00".b * (65544 + lookup.bytesize)
    data[0, 10] = [1, 0, 100, 20000, 10].pack("n*")
    data[10, 2 + lookup_count * 2] = [lookup_count, *Array.new(lookup_count, 65534)].pack("n*")
    data[100, scripts.bytesize] = scripts
    data[20000, features.bytesize] = features
    data[65544, lookup.bytesize] = lookup
    data
  end

  def gpos_feature_spans_binary(offsets:, data:, lookup_count: 2)
    count = offsets.size
    langsys = [0, 0xffff, count, *(0...count)].pack("n*")
    scripts = "#{[1].pack('n')}latn#{[8, 4, 0].pack('n*')}#{langsys}"
    features = [count].pack("n") + offsets.map { |offset| "kern#{[offset].pack('n')}" }.join + data
    lookup = gpos_lookup([gpos_pair_two(coverage: [0], first: {}, second: {}, matrix: [[-1]])])
    lookups = [lookup_count, *Array.new(lookup_count, 2 + lookup_count * 2)].pack("n*") + lookup
    [1, 0, 10, 10 + scripts.bytesize, 10 + scripts.bytesize + features.bytesize].pack("n*") +
      scripts + features + lookups
  end

  def gpos_load_order(order, font_path)
    program = <<~RUBY
      font_path = ARGV.pop
      ARGV.each { |path| require path }
      klass = Fontisan::Tables::Gpos
      raise "wrong superclass" unless klass.superclass == Fontisan::Binary::BaseRecord
      raise "missing reader" unless klass.respond_to?(:read)
      %w[fontisan fontisan/tables/gpos fontisan/tables/gpos/pair_position fontisan/tables/gpos/kerning_pairs].each do |path|
        require path
      end
      raise "duplicate class" unless klass.equal?(Fontisan::Tables::Gpos)
      pairs = Fontisan::FontLoader.load(font_path).table("GPOS").kern_pairs
      raise "wrong kerning" unless pairs[[34, 55]] == -112
      puts "ok"
    RUBY
    Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__),
                   "-e", program, *order, font_path)
  end

  def gpos_overlapping_classes_binary(count: 32, class_values: 2000)
    data = gpos_binary([gpos_lookup(["ignored"])] * count)
    list_offset = data.byteslice(8, 2).unpack1("n")
    header = 2 + count * 2
    positions_base = header + count * 8
    coverage_base = positions_base + (count - 1) * 18 + 60016
    second_base = coverage_base + 6
    first_base = second_base + 4
    body = "\x00".b * (first_base + count * 6 + class_values * 2)
    body[0, header] = [count, *(0...count).map { |index| header + index * 8 }].pack("n*")
    count.times do |index|
      lookup_base = header + index * 8
      position = positions_base + index * 18
      body[lookup_base, 8] = [2, 0, 1, position - lookup_base].pack("n*")
      body[position, 18] = [2, coverage_base - position, 4, 0, first_base + index * 6 - position,
                            second_base - position, 30000, 1, -1].pack("n*")
      body[first_base + index * 6, 6] = [1, index, class_values].pack("n*")
    end
    body[coverage_base, 6] = [1, 1, 2].pack("n*")
    body[second_base, 4] = [2, 0].pack("n*")
    data.byteslice(0, list_offset) + body
  end

  def gpos_overlapping_features_binary(count: 32, indices: 1000)
    langsys = [0, 0xffff, count, *(0...count)].pack("n*")
    scripts = "#{[1].pack('n')}latn#{[8, 4, 0].pack('n*')}#{langsys}"
    records = (0...count).map do |index|
      "kern#{[2 + count * 6 + index * 4].pack('n')}"
    end.join
    features = [count].pack("n") + records + Array.new(count, [0, indices].pack("n*")).join +
      "\x00".b * (indices * 2)
    lookups = [1, 4, 1, 0, 0].pack("n*")
    [1, 0, 10, 10 + scripts.bytesize, 10 + scripts.bytesize + features.bytesize].pack("n*") +
      scripts + features + lookups
  end
end
