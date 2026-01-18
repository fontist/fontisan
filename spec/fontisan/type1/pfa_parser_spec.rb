# frozen_string_literal: true

RSpec.describe Fontisan::Type1::PFAParser do
  describe ".pfa_file?" do
    it "returns true for Adobe Type 1 font header" do
      expect(described_class.pfa_file?("%!PS-AdobeFont-1.0")).to be true
    end

    it "returns true for Adobe 3.0 Resource-Font header" do
      expect(described_class.pfa_file?("%!PS-Adobe-3.0 Resource-Font")).to be true
    end

    it "returns false for nil data" do
      expect(described_class.pfa_file?(nil)).to be false
    end

    it "returns false for empty data" do
      expect(described_class.pfa_file?("")).to be false
    end

    it "returns false for data that is too short" do
      expect(described_class.pfa_file?("short")).to be false
    end

    it "returns false for non-PFA data" do
      expect(described_class.pfa_file?("random text without header")).to be false
    end
  end

  describe "#parse" do
    it "raises ArgumentError for nil data" do
      parser = described_class.new
      expect do
        parser.parse(nil)
      end.to raise_error(ArgumentError, /Data cannot be nil/)
    end

    it "raises ArgumentError for empty data" do
      parser = described_class.new
      expect do
        parser.parse("")
      end.to raise_error(ArgumentError, /Data cannot be empty/)
    end

    it "parses PFA with eexec marker" do
      data = <<~DATA
        %!PS-AdobeFont-1.0: TestFont 1.0
        % Some clear text
        currentfile eexec
        encrypted_data_here
        #{'0' * 512}
        % Cleartext footer
      DATA

      parser = described_class.new
      result = parser.parse(data)

      expect(result.clear_text).to include("%!PS-AdobeFont-1.0")
      expect(result.clear_text).to include("currentfile eexec")
      expect(result.encrypted_hex.strip).to eq("encrypted_data_here")
      expect(result.trailing_text.strip).to eq("% Cleartext footer")
    end

    it "handles PFA without eexec marker" do
      data = "%!PS-AdobeFont-1.0: TestFont\n/all clear text"

      parser = described_class.new
      result = parser.parse(data)

      expect(result.clear_text).to eq(data)
      expect(result.encrypted_hex).to eq("")
      expect(result.trailing_text).to eq("")
    end

    it "normalizes CRLF line endings" do
      data = "%!PS-AdobeFont-1.0\r\ncurrentfile eexec\r\nencrypted\r\n#{'0' * 512}"

      parser = described_class.new
      result = parser.parse(data)

      expect(result.clear_text).not_to include("\r\n")
    end

    it "normalizes CR line endings" do
      data = "%!PS-AdobeFont-1.0\rcurrentfile eexec\rencrypted\r#{'0' * 512}"

      parser = described_class.new
      result = parser.parse(data)

      expect(result.clear_text).not_to include("\r")
    end

    it "skips whitespace after eexec marker" do
      data = "%!PS-AdobeFont-1.0\ncurrentfile eexec\n\t  \nencrypted\n#{'0' * 512}"

      parser = described_class.new
      result = parser.parse(data)

      expect(result.encrypted_hex.strip).to eq("encrypted")
    end

    it "handles encrypted data with spaces" do
      data = <<~DATA
        %!PS-AdobeFont-1.0
        currentfile eexec
        01 02 03 04 05 06
        #{'0' * 512}
      DATA

      parser = described_class.new
      result = parser.parse(data)

      expect(result.encrypted_hex.strip).to eq("01 02 03 04 05 06")
    end

    it "handles trailing text after zeros" do
      data = <<~DATA
        %!PS-AdobeFont-1.0
        currentfile eexec
        encrypted
        #{'0' * 512}
        % This is trailing text
        /FontName /Test def
      DATA

      parser = described_class.new
      result = parser.parse(data)

      expect(result.trailing_text).to include("% This is trailing text")
      expect(result.trailing_text).to include("/FontName /Test def")
    end

    context "error handling" do
      it "raises error when zero marker is missing" do
        data = "%!PS-AdobeFont-1.0\ncurrentfile eexec\nencrypted\nbut no zeros"

        parser = described_class.new

        expect { parser.parse(data) }
          .to raise_error(Fontisan::Error, /cannot find zero marker/)
      end
    end
  end

  describe "#parsed?" do
    it "returns false before parsing" do
      parser = described_class.new
      expect(parser.parsed?).to be false
    end

    it "returns true after parsing" do
      parser = described_class.new
      parser.parse("%!PS-AdobeFont-1.0")
      expect(parser.parsed?).to be true
    end
  end

  describe "#encrypted_binary" do
    it "converts hex to binary" do
      data = <<~DATA
        %!PS-AdobeFont-1.0
        currentfile eexec
        48656c6c6f
        #{'0' * 512}
      DATA

      parser = described_class.new
      parser.parse(data)

      expect(parser.encrypted_binary).to eq("Hello")
    end

    it "handles hex with spaces" do
      data = <<~DATA
        %!PS-AdobeFont-1.0
        currentfile eexec
        48 65 6c 6c 6f
        #{'0' * 512}
      DATA

      parser = described_class.new
      parser.parse(data)

      expect(parser.encrypted_binary).to eq("Hello")
    end

    it "returns empty string for no encrypted data" do
      data = "%!PS-AdobeFont-1.0"

      parser = described_class.new
      parser.parse(data)

      expect(parser.encrypted_binary).to eq("")
    end
  end
end
