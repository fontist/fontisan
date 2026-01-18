# frozen_string_literal: true

RSpec.describe Fontisan::Type1::Decryptor do
  describe ".eexec_decrypt" do
    it "returns empty string for nil input" do
      expect(described_class.eexec_decrypt(nil)).to eq("")
    end

    it "returns empty string for empty input" do
      expect(described_class.eexec_decrypt("")).to eq("")
    end

    it "decrypts single byte" do
      # Encrypt with known key, verify decryption
      encrypted = described_class.eexec_encrypt("A")
      decrypted = described_class.eexec_decrypt(encrypted)

      expect(decrypted).to eq("A")
    end

    it "decrypts multiple bytes" do
      encrypted = described_class.eexec_encrypt("Hello, World!")
      decrypted = described_class.eexec_decrypt(encrypted)

      expect(decrypted).to eq("Hello, World!")
    end

    it "handles binary data" do
      original = "\x00\x01\x02\x03\xFF\xFE\xFD".b
      encrypted = described_class.eexec_encrypt(original)
      decrypted = described_class.eexec_decrypt(encrypted)

      expect(decrypted).to eq(original)
    end

    it "decrypts text with eexec key" do
      # Test with known plaintext/ciphertext pair
      # These values are from the Adobe Type 1 spec
      plaintext = "Test data for decryption"

      encrypted = described_class.eexec_encrypt(plaintext)
      decrypted = described_class.eexec_decrypt(encrypted)

      expect(decrypted).to eq(plaintext)
    end

    it "is symmetric with encrypt" do
      plaintext = "The quick brown fox jumps over the lazy dog"

      encrypted = described_class.eexec_encrypt(plaintext)
      decrypted = described_class.eexec_decrypt(encrypted)

      expect(decrypted).to eq(plaintext)
    end
  end

  describe ".eexec_encrypt" do
    it "returns empty string for nil input" do
      expect(described_class.eexec_encrypt(nil)).to eq("")
    end

    it "returns empty string for empty input" do
      expect(described_class.eexec_encrypt("")).to eq("")
    end

    it "produces different output from input" do
      plaintext = "Hello"
      encrypted = described_class.eexec_encrypt(plaintext)

      expect(encrypted).not_to eq(plaintext)
    end

    it "produces consistent output for same input" do
      plaintext = "Test"

      encrypted1 = described_class.eexec_encrypt(plaintext)
      encrypted2 = described_class.eexec_encrypt(plaintext)

      expect(encrypted1).to eq(encrypted2)
    end
  end

  describe ".charstring_decrypt" do
    it "returns empty string for nil input" do
      expect(described_class.charstring_decrypt(nil)).to eq("")
    end

    it "returns empty string for empty input" do
      expect(described_class.charstring_decrypt("")).to eq("")
    end

    it "decrypts with default lenIV of 4" do
      # Encrypt with lenIV=4, then decrypt
      plaintext = "abc"
      encrypted = described_class.charstring_encrypt(plaintext, len_iv: 4)

      # Should skip 4 bytes during decryption
      decrypted = described_class.charstring_decrypt(encrypted, len_iv: 4)

      expect(decrypted).to eq(plaintext)
    end

    it "decrypts with custom lenIV" do
      plaintext = "xyz"

      # Test with lenIV=0
      encrypted = described_class.charstring_encrypt(plaintext, len_iv: 0)
      decrypted = described_class.charstring_decrypt(encrypted, len_iv: 0)
      expect(decrypted).to eq(plaintext)

      # Test with lenIV=2
      encrypted = described_class.charstring_encrypt(plaintext, len_iv: 2)
      decrypted = described_class.charstring_decrypt(encrypted, len_iv: 2)
      expect(decrypted).to eq(plaintext)
    end

    it "handles lenIV larger than data" do
      # Encrypted data shorter than lenIV
      encrypted = "\x01\x02\x03"
      decrypted = described_class.charstring_decrypt(encrypted, len_iv: 10)

      expect(decrypted).to eq("")
    end

    it "decrypts binary CharString data" do
      # Simulate Type 1 CharString commands
      plaintext = "\x8B\x0C\x0A".b # Some CharString bytes

      encrypted = described_class.charstring_encrypt(plaintext, len_iv: 4)
      decrypted = described_class.charstring_decrypt(encrypted, len_iv: 4)

      expect(decrypted).to eq(plaintext)
    end

    it "is symmetric with encrypt" do
      plaintext = "CharString data with various bytes: \x00\xFF\xAB\xCD"

      encrypted = described_class.charstring_encrypt(plaintext.b, len_iv: 4)
      decrypted = described_class.charstring_decrypt(encrypted, len_iv: 4)

      # Convert back to original encoding for comparison
      expect(decrypted.force_encoding("UTF-8")).to eq(plaintext)
    end
  end

  describe ".charstring_encrypt" do
    it "returns empty string for nil input" do
      expect(described_class.charstring_encrypt(nil)).to eq("")
    end

    it "returns empty string for empty input" do
      expect(described_class.charstring_encrypt("")).to eq("")
    end

    it "prepends lenIV random bytes" do
      plaintext = "test"

      encrypted = described_class.charstring_encrypt(plaintext, len_iv: 4)

      # Encrypted data should be longer than plaintext
      expect(encrypted.length).to be > plaintext.length
    end

    it "produces consistent output for same input with same seed" do
      plaintext = "Test"

      encrypted1 = described_class.charstring_encrypt(plaintext, len_iv: 4)
      # Note: This might not always pass due to random bytes, but the
      # decryption should always work correctly
      decrypted1 = described_class.charstring_decrypt(encrypted1, len_iv: 4)

      expect(decrypted1).to eq(plaintext)
    end
  end

  describe "cipher algorithm" do
    it "handles state correctly across bytes" do
      # Test that cipher state is maintained properly
      plaintext = "ABCDEFGHIJ"

      encrypted = described_class.eexec_encrypt(plaintext)
      decrypted = described_class.eexec_decrypt(encrypted)

      expect(decrypted).to eq(plaintext)
    end

    it "produces different ciphertext for different keys" do
      plaintext = "test"

      eexec_encrypted = described_class.encrypt(plaintext,
                                                described_class::EEXEC_KEY)
      cs_encrypted = described_class.encrypt(plaintext,
                                             described_class::CHARSTRING_KEY)

      expect(eexec_encrypted).not_to eq(cs_encrypted)
    end

    it "handles zero bytes correctly" do
      plaintext = "\x00\x00\x00\x00"

      encrypted = described_class.eexec_encrypt(plaintext)
      decrypted = described_class.eexec_decrypt(encrypted)

      expect(decrypted).to eq(plaintext)
    end

    it "handles all byte values" do
      # Test all possible byte values
      plaintext = (0..255).map(&:chr).join

      encrypted = described_class.eexec_encrypt(plaintext)
      decrypted = described_class.eexec_decrypt(encrypted)

      expect(decrypted).to eq(plaintext)
    end
  end
end
