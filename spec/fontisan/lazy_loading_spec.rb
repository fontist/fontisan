# frozen_string_literal: true

require "spec_helper"
require "benchmark"

RSpec.describe "Lazy Table Loading" do
  let(:font_path) { fixture_path("fonts/NotoSans-Regular.ttf") }

  describe "lazy loading behavior" do
    it "does not load table data upfront with lazy: true" do
      font = Fontisan::FontLoader.load(font_path, lazy: true)

      # Table data should be empty initially
      expect(font.table_data).to be_empty
    end

    it "loads table data on first access" do
      font = Fontisan::FontLoader.load(font_path, lazy: true)

      # Access name table
      name_table = font.table("name")

      # Now name table data should be loaded
      expect(font.table_data).to have_key("name")
      expect(name_table).not_to be_nil
    end

    it "caches parsed table instances" do
      font = Fontisan::FontLoader.load(font_path, lazy: true)

      # Access same table twice
      table1 = font.table("name")
      table2 = font.table("name")

      # Should be same instance (cached)
      expect(table1.object_id).to eq(table2.object_id)
    end

    it "only loads accessed tables" do
      font = Fontisan::FontLoader.load(font_path, lazy: true)

      # Access only name table
      font.table("name")

      # Other tables should not be loaded
      expect(font.table_data.size).to eq(1)
      expect(font.table_data).to have_key("name")
      expect(font.table_data).not_to have_key("GSUB")
      expect(font.table_data).not_to have_key("GPOS")
      expect(font.table_data).not_to have_key("cmap")
    end

    it "loads multiple tables independently" do
      font = Fontisan::FontLoader.load(font_path, lazy: true)

      # Access multiple tables
      font.table("name")
      font.table("head")
      font.table("hhea")

      # Should have loaded only these three
      expect(font.table_data.size).to eq(3)
      expect(font.table_data).to have_key("name")
      expect(font.table_data).to have_key("head")
      expect(font.table_data).to have_key("hhea")
    end

    it "returns nil for non-existent tables" do
      font = Fontisan::FontLoader.load(font_path, lazy: true)

      # Try to access non-existent table
      result = font.table("ZZZZ")

      expect(result).to be_nil
    end

    it "keeps IO source reference when lazy loading" do
      font = Fontisan::FontLoader.load(font_path, lazy: true)

      expect(font.io_source).not_to be_nil
      expect(font.io_source).to be_a(File)
      expect(font.lazy_load_enabled).to be true

      font.close
    end
  end

  describe "performance" do
    it "is faster than eager loading for single table access" do
      eager_time = Benchmark.realtime do
        10.times do
          font = Fontisan::FontLoader.load(font_path, lazy: false)
          font.table("name")  # Only access one table
        end
      end

      lazy_time = Benchmark.realtime do
        10.times do
          font = Fontisan::FontLoader.load(font_path, lazy: true)
          font.table("name")  # Only access one table
          font.close
        end
      end

      puts "\nLazy loading performance (single table):"
      puts "  Eager: #{eager_time.round(3)}s"
      puts "  Lazy:  #{lazy_time.round(3)}s"
      puts "  Speedup: #{(eager_time / lazy_time).round(1)}x"

      expect(lazy_time).to be < eager_time
    end

    it "has similar performance to eager loading when accessing all tables" do
      eager_time = Benchmark.realtime do
        5.times do
          font = Fontisan::FontLoader.load(font_path, lazy: false)
          # Access all common tables
          font.table("name")
          font.table("head")
          font.table("hhea")
          font.table("maxp")
          font.table("post")
          font.table("cmap")
        end
      end

      lazy_time = Benchmark.realtime do
        5.times do
          font = Fontisan::FontLoader.load(font_path, lazy: true)
          # Access same tables
          font.table("name")
          font.table("head")
          font.table("hhea")
          font.table("maxp")
          font.table("post")
          font.table("cmap")
          font.close
        end
      end

      puts "\nLazy loading performance (multiple tables):"
      puts "  Eager: #{eager_time.round(3)}s"
      puts "  Lazy:  #{lazy_time.round(3)}s"
      puts "  Ratio: #{(lazy_time / eager_time).round(2)}x"

      # Should be within 30% of eager loading
      expect(lazy_time).to be < (eager_time * 1.3)
    end
  end

  describe "cleanup" do
    it "closes file handle when explicitly closed" do
      font = Fontisan::FontLoader.load(font_path, lazy: true)
      io = font.io_source

      expect(io).not_to be_closed

      font.close

      expect(io).to be_closed
      expect(font.io_source).to be_nil
    end

    it "does not error when closing already closed font" do
      font = Fontisan::FontLoader.load(font_path, lazy: true)

      font.close
      expect { font.close }.not_to raise_error
    end

    it "can still access cached tables after closing" do
      font = Fontisan::FontLoader.load(font_path, lazy: true)

      # Access table before closing
      name_table = font.table("name")
      family = name_table.english_name(Fontisan::Tables::Name::FAMILY)

      font.close

      # Can still access cached table
      expect(font.table("name")).to eq(name_table)
      expect(name_table.english_name(Fontisan::Tables::Name::FAMILY)).to eq(family)
    end

    it "cannot load new tables after closing" do
      font = Fontisan::FontLoader.load(font_path, lazy: true)

      # Access one table
      font.table("name")

      font.close

      # Try to access unloaded table - should return nil
      expect(font.table("head")).to be_nil
    end
  end

  describe "default behavior" do
    it "works with lazy: false (eager loading)" do
      font = Fontisan::FontLoader.load(font_path, lazy: false)

      # Should have loaded all table data upfront
      expect(font.table_data.size).to be > 5
      expect(font.lazy_load_enabled).to be false
      expect(font.io_source).to be_nil

      # Should be able to access tables
      expect(font.table("name")).not_to be_nil
      expect(font.table("head")).not_to be_nil
    end

    it "defaults to eager loading" do
      font = Fontisan::FontLoader.load(font_path)

      # Default should be eager loading (lazy: false)
      expect(font.lazy_load_enabled).to be false
      expect(font.table_data.size).to be > 5
    end

    it "maintains same API for table access regardless of lazy setting" do
      eager_font = Fontisan::FontLoader.load(font_path, lazy: false)
      lazy_font = Fontisan::FontLoader.load(font_path, lazy: true)

      # Both should return same values
      expect(eager_font.family_name).to eq(lazy_font.family_name)
      expect(eager_font.subfamily_name).to eq(lazy_font.subfamily_name)
      expect(eager_font.full_name).to eq(lazy_font.full_name)

      lazy_font.close
    end

    it "works with metadata mode and lazy loading" do
      font = Fontisan::FontLoader.load(font_path, mode: :metadata, lazy: true)

      # Should not load anything upfront
      expect(font.table_data).to be_empty

      # Access name table
      name = font.table("name")
      expect(name).not_to be_nil
      expect(font.table_data.size).to eq(1)

      font.close
    end
  end

  describe "edge cases" do
    it "handles invalid file path" do
      expect {
        Fontisan::FontLoader.load("nonexistent.ttf", lazy: true)
      }.to raise_error(Errno::ENOENT)
    end

    it "handles accessing same table multiple times" do
      font = Fontisan::FontLoader.load(font_path, lazy: true)

      # Access table multiple times
      5.times { font.table("name") }

      # Should only have loaded it once
      expect(font.table_data.size).to eq(1)

      font.close
    end

    it "handles table access before and after other operations" do
      font = Fontisan::FontLoader.load(font_path, lazy: true)

      # Access tables in various orders
      name1 = font.table("name")
      head = font.table("head")
      name2 = font.table("name")

      expect(name1.object_id).to eq(name2.object_id)
      expect(head).not_to be_nil

      font.close
    end
  end

  describe "TrueTypeFont direct usage" do
    it "supports lazy loading via from_file" do
      font = Fontisan::TrueTypeFont.from_file(font_path, lazy: true)

      expect(font.lazy_load_enabled).to be true
      expect(font.table_data).to be_empty

      font.table("name")
      expect(font.table_data).to have_key("name")

      font.close
    end

    it "defaults to eager loading in from_file" do
      font = Fontisan::TrueTypeFont.from_file(font_path)

      expect(font.lazy_load_enabled).to be false
    end
  end
end