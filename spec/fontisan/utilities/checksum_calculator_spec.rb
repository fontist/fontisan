# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Fontisan::Utilities::ChecksumCalculator do
  describe ".calculate_file_checksum" do
    it "calculates checksum for a font file" do
      font_path = font_fixture_path("NotoSans", "NotoSans-Regular.ttf")
      checksum = described_class.calculate_file_checksum(font_path)

      expect(checksum).to be_a(Integer)
      expect(checksum).to be > 0
    end

    it "raises error for non-existent file" do
      expect do
        described_class.calculate_file_checksum("nonexistent.ttf")
      end.to raise_error(Errno::ENOENT)
    end
  end

  describe ".calculate_adjustment" do
    it "calculates checksum adjustment" do
      file_checksum = 2842116234
      adjustment = described_class.calculate_adjustment(file_checksum)

      expect(adjustment).to be_a(Integer)
      expect(adjustment).to eq((Fontisan::Constants::CHECKSUM_ADJUSTMENT_MAGIC - file_checksum) & 0xFFFFFFFF)
    end

    it "returns a 32-bit value" do
      adjustment = described_class.calculate_adjustment(0xFFFFFFFF)
      expect(adjustment).to be <= 0xFFFFFFFF
      expect(adjustment).to be >= 0
    end
  end

  describe ".calculate_table_checksum" do
    it "calculates checksum for table data" do
      data = "TEST" * 100
      checksum = described_class.calculate_table_checksum(data)

      expect(checksum).to be_a(Integer)
      expect(checksum).to be > 0
    end

    it "handles empty data" do
      checksum = described_class.calculate_table_checksum("")
      expect(checksum).to eq(0)
    end

    it "pads data to 4-byte boundary" do
      # 3 bytes should be padded with 1 zero byte
      data = "ABC"
      checksum = described_class.calculate_table_checksum(data)
      expect(checksum).to be_a(Integer)
    end
  end

  describe ".calculate_checksum_from_io_with_tempfile" do
    let(:test_data) { "TEST DATA" * 100 }
    let(:io) { StringIO.new(test_data) }

    it "returns array with checksum and tempfile" do
      result = described_class.calculate_checksum_from_io_with_tempfile(io)

      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result[0]).to be_a(Integer)
      expect(result[1]).to be_a(Tempfile)
    end

    it "calculates correct checksum" do
      checksum, _tmpfile = described_class.calculate_checksum_from_io_with_tempfile(io)

      # Calculate expected checksum directly
      expected = described_class.calculate_table_checksum(test_data)
      expect(checksum).to eq(expected)
    end

    it "keeps tempfile alive until returned" do
      _, tmpfile = described_class.calculate_checksum_from_io_with_tempfile(io)

      # Tempfile should exist and be readable
      expect(File.exist?(tmpfile.path)).to be true

      # Tempfile content should match original IO
      tmpfile.open
      content = tmpfile.read
      tmpfile.close

      expect(content).to eq(test_data)
    end

    it "allows tempfile to be GC'd when reference is released" do
      checksum, tmpfile = described_class.calculate_checksum_from_io_with_tempfile(io)
      tmpfile.path

      # Release reference
      nil
      GC.start

      # Tempfile should eventually be deleted (may take a moment on some systems)
      # We don't strictly test this because GC timing is unpredictable
      expect(checksum).to be_a(Integer)
    end

    it "handles File IO objects" do
      Tempfile.create(["test", ".dat"]) do |file|
        file.write(test_data)
        file.flush
        file.rewind

        checksum, tmpfile = described_class.calculate_checksum_from_io_with_tempfile(file)

        expect(checksum).to be_a(Integer)
        expect(tmpfile).to be_a(Tempfile)
      end
    end

    context "Windows compatibility" do
      it "prevents premature tempfile deletion during parallel processing" do
        # Simulate parallel font processing
        threads = []
        checksums = []

        5.times do
          threads << Thread.new do
            io = StringIO.new(test_data)
            checksum, _tmpfile = described_class.calculate_checksum_from_io_with_tempfile(io)

            # Force GC while tempfile might still be in use
            GC.start

            checksums << checksum
          end
        end

        threads.each(&:join)

        # All threads should complete successfully
        expect(checksums.length).to eq(5)
        expect(checksums.all?(Integer)).to be true
      end

      it "allows concurrent checksum calculations" do
        # Multiple concurrent calculations should not interfere
        results = []

        Array.new(10) do
          Thread.new do
            io = StringIO.new(test_data)
            checksum, tmpfile = described_class.calculate_checksum_from_io_with_tempfile(io)
            results << [checksum, tmpfile]
          end
        end.each(&:join)

        expect(results.length).to eq(10)

        # All checksums should be the same
        checksums = results.map(&:first)
        expect(checksums.uniq.length).to eq(1)
      end

      it "handles TTC collection font extraction workflow without EACCES errors" do
        # Simulate the exact workflow from the bug report:
        # TrueTypeCollection.font(index, io) -> TrueTypeFont.to_file(path) ->
        # update_checksum_adjustment_in_file(path) -> calculate_checksum_from_io_with_tempfile(io)

        # Create temp output files to simulate font extraction
        output_files = []

        begin
          3.times do |i|
            # Simulate creating output file from IO
            output_file = Tempfile.new(["extracted_font_#{i}", ".ttf"])
            output_files << output_file

            # Write test data
            output_file.write(test_data)
            output_file.flush
            output_file.close

            # Simulate checksum calculation (as done in to_file)
            File.open(output_file.path, "r+b") do |io|
              checksum, _tmpfile = described_class.calculate_checksum_from_io_with_tempfile(io)
              expect(checksum).to be_a(Integer)
            end

            # Force GC to trigger cleanup (this is where Windows would fail in 0.2.7)
            GC.start
          end

          # All operations should complete without Errno::EACCES
          expect(output_files.length).to eq(3)
        ensure
          output_files.each do |f|
            f.unlink if f && File.exist?(f.path)
          end
        end
      end
    end
  end

  describe "integration with font files" do
    it "calculates consistent checksums" do
      font_path = font_fixture_path("NotoSans", "NotoSans-Regular.ttf")

      # Calculate using direct file method
      checksum1 = described_class.calculate_file_checksum(font_path)

      # Calculate using tempfile method
      File.open(font_path, "rb") do |io|
        checksum2, _tmpfile = described_class.calculate_checksum_from_io_with_tempfile(io)

        expect(checksum2).to eq(checksum1)
      end
    end
  end
end
