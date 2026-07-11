# frozen_string_literal: true

require "tmpdir"

RSpec.describe Fontisan::Ufo::ImageSet do
  describe ".load_from_dir" do
    it "returns an empty ImageSet when the directory does not exist" do
      is = described_class.load_from_dir("/nonexistent/path/images")
      expect(is).to be_empty
    end

    it "reads PNG files from the directory" do
      Dir.mktmpdir do |tmp|
        images_dir = File.join(tmp, "images")
        FileUtils.mkpath(images_dir)
        File.binwrite(File.join(images_dir, "a.png"), "PNG-BYTES-A")
        File.binwrite(File.join(images_dir, "b.png"), "PNG-BYTES-B")

        is = described_class.load_from_dir(images_dir)
        expect(is.count).to eq(2)
        expect(is.find("a.png").bytes).to eq("PNG-BYTES-A")
        expect(is.find("b.png").bytes).to eq("PNG-BYTES-B")
      end
    end

    it "computes sha256 for each image" do
      Dir.mktmpdir do |tmp|
        images_dir = File.join(tmp, "images")
        FileUtils.mkpath(images_dir)
        File.binwrite(File.join(images_dir, "x.png"), "hello")

        is = described_class.load_from_dir(images_dir)
        expect(is.find("x.png").sha).to eq(
          Digest::SHA256.hexdigest("hello"),
        )
      end
    end

    it "skips subdirectories" do
      Dir.mktmpdir do |tmp|
        images_dir = File.join(tmp, "images")
        FileUtils.mkpath(images_dir)
        FileUtils.mkpath(File.join(images_dir, "subdir"))
        File.binwrite(File.join(images_dir, "a.png"), "A")

        is = described_class.load_from_dir(images_dir)
        expect(is.count).to eq(1)
      end
    end
  end

  describe "#register_file" do
    it "registers an image with computed sha" do
      is = described_class.new
      img = is.register_file("test.png", "data")
      expect(img.file_name).to eq("test.png")
      expect(img.bytes).to eq("data")
      expect(img.sha).to eq(Digest::SHA256.hexdigest("data"))
    end

    it "overwrites an existing image with the same name" do
      is = described_class.new
      is.register_file("test.png", "old")
      is.register_file("test.png", "new")
      expect(is.find("test.png").bytes).to eq("new")
    end
  end

  describe "#find / #[]" do
    it "finds by filename" do
      is = described_class.new
      is.register_file("a.png", "A")
      expect(is.find("a.png").bytes).to eq("A")
      expect(is["a.png"].bytes).to eq("A")
    end

    it "returns nil for missing files" do
      is = described_class.new
      expect(is.find("missing.png")).to be_nil
    end
  end

  describe "#each" do
    it "iterates over images" do
      is = described_class.new
      is.register_file("a.png", "A")
      is.register_file("b.png", "B")
      names = is.each.map(&:file_name)
      expect(names).to contain_exactly("a.png", "b.png")
    end

    it "returns an enumerator when no block given" do
      is = described_class.new
      is.register_file("a.png", "A")
      expect(is.each).to be_an(Enumerator)
    end
  end

  describe "#write_to_dir" do
    it "writes all images to the target directory" do
      Dir.mktmpdir do |tmp|
        is = described_class.new
        is.register_file("a.png", "A")
        is.register_file("b.png", "B")
        target = File.join(tmp, "out", "images")
        is.write_to_dir(target)

        expect(File.binread(File.join(target, "a.png"))).to eq("A")
        expect(File.binread(File.join(target, "b.png"))).to eq("B")
      end
    end
  end

  describe "round-trip" do
    it "loads → writes → loads produces the same image set" do
      Dir.mktmpdir do |tmp|
        src = File.join(tmp, "src")
        FileUtils.mkpath(src)
        File.binwrite(File.join(src, "a.png"), "AAA")
        File.binwrite(File.join(src, "b.png"), "BBB")

        is1 = described_class.load_from_dir(src)
        dest = File.join(tmp, "dest")
        is1.write_to_dir(dest)
        is2 = described_class.load_from_dir(dest)

        expect(is2.count).to eq(is1.count)
        is1.each do |img|
          expect(is2.find(img.file_name).bytes).to eq(img.bytes)
          expect(is2.find(img.file_name).sha).to eq(img.sha)
        end
      end
    end
  end
end
