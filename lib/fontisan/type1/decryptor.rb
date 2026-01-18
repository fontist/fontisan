# frozen_string_literal: true

module Fontisan
  module Type1
    # Decryption utilities for Type 1 fonts
    #
    # [`Decryptor`](lib/fontisan/type1/decryptor.rb) handles the two types of
    # encryption used in Adobe Type 1 fonts:
    #
    # 1. **eexec encryption**: Protects the font's private dictionary and
    #    CharStrings with key 55665
    # 2. **CharString encryption**: Individual CharStrings within the eexec
    #    portion with key 4330
    #
    # Both use the same cipher algorithm but with different keys.
    # The algorithm uses cipher feedback, where the ciphertext is used
    # to modify the key for subsequent bytes.
    #
    # Algorithm (from Adobe Type 1 Font Format):
    #   plain = (cipher XOR (R >> 8)) AND 0xFF
    #   R = ((cipher + R) * 52845 + 22719) AND 0xFFFF
    #
    # @example Decrypt eexec portion
    #   encrypted = Fontisan::Type1::PFAParser.new.parse(data).encrypted_binary
    #   decrypted = Fontisan::Type1::Decryptor.eexec_decrypt(encrypted)
    #
    # @example Decrypt CharString
    #   encrypted_charstring = "\x80\x00\x01..."
    #   decrypted = Fontisan::Type1::Decryptor.charstring_decrypt(encrypted_charstring, len_iv: 4)
    #
    # @see https://www.adobe.com/devnet/font/pdfs/Type1.pdf
    module Decryptor
      # Default lenIV value (number of random bytes at start of encrypted CharString)
      DEFAULT_LEN_IV = 4

      # eexec encryption key
      EEXEC_KEY = 55665

      # CharString encryption key
      CHARSTRING_KEY = 4330

      # Cipher update constants
      CIPHER_MULT = 52845
      CIPHER_ADD = 22719
      CIPHER_MASK = 0xFFFF

      # Decrypt eexec encrypted data
      #
      # The eexec cipher is used to encrypt the private dictionary and
      # CharStrings portion of a Type 1 font.
      #
      # @param data [String] Encrypted binary data
      # @return [String] Decrypted data
      #
      # @example Decrypt eexec portion
      #   decrypted = Fontisan::Type1::Decryptor.eexec_decrypt(encrypted_data)
      def self.eexec_decrypt(data)
        return "" if data.nil? || data.empty?

        decrypt(data, EEXEC_KEY)
      end

      # Encrypt data using eexec cipher
      #
      # @param data [String] Plain text data
      # @return [String] Encrypted data
      def self.eexec_encrypt(data)
        return "" if data.nil? || data.empty?

        encrypt(data, EEXEC_KEY)
      end

      # Decrypt Type 1 CharString
      #
      # CharStrings are encrypted within the eexec portion using a different
      # key (4330). The lenIV parameter specifies how many random bytes
      # precede the actual CharString data (default is 4).
      #
      # @param data [String] Encrypted CharString data
      # @param len_iv [Integer] Number of bytes to skip after decryption
      # @return [String] Decrypted CharString data
      #
      # @example Decrypt CharString with default lenIV
      #   decrypted = Fontisan::Type1::Decryptor.charstring_decrypt(encrypted)
      #
      # @example Decrypt CharString with custom lenIV
      #   decrypted = Fontisan::Type1::Decryptor.charstring_decrypt(encrypted, len_iv: 0)
      def self.charstring_decrypt(data, len_iv: DEFAULT_LEN_IV)
        return "" if data.nil? || data.empty?

        decrypted = decrypt(data, CHARSTRING_KEY)

        # Skip lenIV bytes (random bytes added during encryption)
        if len_iv.positive?
          if len_iv >= decrypted.length
            # lenIV is larger than data - return empty
            return ""
          end

          decrypted = decrypted.byteslice(len_iv..-1)
        end

        decrypted
      end

      # Encrypt data using CharString cipher
      #
      # @param data [String] Plain CharString data
      # @param len_iv [Integer] Number of random bytes to prepend
      # @return [String] Encrypted CharString data
      def self.charstring_encrypt(data, len_iv: DEFAULT_LEN_IV)
        return "" if data.nil? || data.empty?

        # Ensure binary encoding before concatenation
        data = data.b if data.respond_to?(:b)

        # Prepend lenIV random bytes
        if len_iv.positive?
          random_bytes = Array.new(len_iv) { rand(256) }.pack("C*")
          data = random_bytes + data
        end

        encrypt(data, CHARSTRING_KEY)
      end

      # Decrypt using Type 1 cipher
      #
      # The cipher processes data byte by byte, maintaining state
      # across iterations using cipher feedback.
      #
      # Algorithm:
      #   plain = (cipher XOR (R >> 8)) AND 0xFF
      #   R = ((cipher + R) * 52845 + 22719) AND 0xFFFF
      #
      # @param data [String] Encrypted data
      # @param key [Integer] Cipher key (55665 for eexec, 4330 for CharString)
      # @return [String] Decrypted data
      def self.decrypt(data, key)
        result = String.new(capacity: data.length)
        r = key

        data.each_byte do |cipher|
          # plain = (cipher XOR (R >> 8)) AND 0xFF
          plain = (cipher ^ (r >> 8)) & 0xFF
          result << plain

          # R = ((cipher + R) * 52845 + 22719) AND 0xFFFF
          r = ((cipher + r) * CIPHER_MULT + CIPHER_ADD) & CIPHER_MASK
        end

        result
      end

      # Encrypt using Type 1 cipher
      #
      # The encryption algorithm is symmetric with decryption,
      # producing the ciphertext that decrypts to the original plaintext.
      #
      # Algorithm:
      #   cipher = (plain XOR (R >> 8)) AND 0xFF
      #   R = ((cipher + R) * 52845 + 22719) AND 0xFFFF
      #
      # @param data [String] Plain data
      # @param key [Integer] Cipher key
      # @return [String] Encrypted data
      def self.encrypt(data, key)
        result = String.new(capacity: data.length)
        r = key

        data.each_byte do |plain|
          # cipher = (plain XOR (R >> 8)) AND 0xFF
          cipher = (plain ^ (r >> 8)) & 0xFF
          result << cipher

          # R = ((cipher + R) * 52845 + 22719) AND 0xFFFF
          r = ((cipher + r) * CIPHER_MULT + CIPHER_ADD) & CIPHER_MASK
        end

        result
      end
    end
  end
end
