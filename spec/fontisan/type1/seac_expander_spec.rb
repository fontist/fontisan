# frozen_string_literal: true

RSpec.describe Fontisan::Type1::SeacExpander, "seac composite decomposition" do
  subject(:expander) { described_class.new(charstrings, private_dict) }

  let(:charstrings) { Fontisan::Type1::CharStrings.new }
  let(:private_dict) { Fontisan::Type1::PrivateDict.new }

  before do
    # Set up sample CharStrings data
    charstrings.instance_variable_set(:@charstrings, {
                                        "A" => create_charstring([:hsbw, 100, 0]), # Base 'A'
                                        "grave" => create_charstring([:hsbw, 50, 100, :endchar]), # Accent 'grave'
                                        ".notdef" => create_charstring([:hsbw,
                                                                        500, 0, :endchar]),
                                      })
    charstrings.instance_variable_set(:@glyph_names, ["A", "grave", ".notdef"])
    # Set up encoding map: character code -> glyph name
    charstrings.instance_variable_set(:@encoding, {
                                        65 => "A", # ASCII 'A'
                                        96 => "grave", # ASCII '`' (grave/quoteleft)
                                      })
  end

  describe "#initialize" do
    it "creates an expander with CharStrings and PrivateDict" do
      expect(expander.charstrings).to eq(charstrings)
      expect(expander.private_dict).to eq(private_dict)
    end
  end

  describe "#composite?" do
    it "returns false for non-composite glyphs" do
      # Add a simple glyph (no seac operator)
      simple_charstring = create_charstring([:hsbw, 100, 0, :endchar])
      charstrings.instance_variable_set(:@charstrings,
                                        { "B" => simple_charstring })

      expect(expander.composite?("B")).to be false
    end

    it "returns true for seac composite glyphs" do
      # Add a seac composite
      seac_charstring = create_seac_charstring(100, 200, 50, 65, 96) # A + grave
      charstrings.instance_variable_set(:@charstrings,
                                        { "Agrave" => seac_charstring })

      expect(expander.composite?("Agrave")).to be true
    end

    it "returns false when glyph doesn't exist" do
      expect(expander.composite?("NonExistent")).to be false
    end
  end

  describe "#decompose" do
    context "with a simple seac composite" do
      let(:base_charstring) { create_charstring([:hsbw, 100, 0]) }
      let(:accent_charstring) { create_charstring([:hsbw, 50, 100]) }

      before do
        # Create a seac composite for "Agrave"
        # bchar=65 ('A'), achar=96 ('`' which is grave accent)
        seac_data = create_seac_charstring(100, 200, 50, 65, 96)

        charstrings.instance_variable_set(:@charstrings, {
                                            "Agrave" => seac_data,
                                            "A" => base_charstring,
                                            "grave" => accent_charstring,
                                          })
        charstrings.instance_variable_set(:@glyph_names,
                                          ["Agrave", "A", "grave"])
        # Set up encoding map for character code to glyph name lookup
        charstrings.instance_variable_set(:@encoding, {
                                            65 => "A", # ASCII 'A'
                                            96 => "grave", # ASCII '`' (grave/quoteleft)
                                          })
      end

      it "decomposes a seac composite into merged CharString" do
        result = expander.decompose("Agrave")

        expect(result).to be_a(String)
        expect(result).not_to be_empty
      end

      it "returns nil for non-composite glyphs" do
        result = expander.decompose("A")

        expect(result).to be_nil
      end

      it "returns nil for non-existent glyphs" do
        result = expander.decompose("NonExistent")

        expect(result).to be_nil
      end
    end

    context "when base glyph is not found" do
      before do
        seac_data = create_seac_charstring(100, 200, 50, 65, 96)
        charstrings.instance_variable_set(:@charstrings, {
                                            "Agrave" => seac_data,
                                            # Missing "A" base glyph
                                          })
        # Set up encoding map without the base glyph
        charstrings.instance_variable_set(:@encoding, {
                                            96 => "grave", # Only accent glyph available
                                          })
      end

      it "raises an error" do
        expect do
          expander.decompose("Agrave")
        end.to raise_error(Fontisan::Error, /Base glyph.*not found/)
      end
    end

    context "when accent glyph is not found" do
      before do
        seac_data = create_seac_charstring(100, 200, 50, 65, 96)
        charstrings.instance_variable_set(:@charstrings, {
                                            "Agrave" => seac_data,
                                            "A" => create_charstring([:hsbw,
                                                                      100, 0]),
                                            # Missing "grave" accent glyph
                                          })
        # Set up encoding map without the accent glyph
        charstrings.instance_variable_set(:@encoding, {
                                            65 => "A", # Only base glyph available
                                          })
      end

      it "raises an error" do
        expect do
          expander.decompose("Agrave")
        end.to raise_error(Fontisan::Error, /Accent glyph.*not found/)
      end
    end
  end

  describe "#composite_glyphs" do
    it "returns empty array when no composites exist" do
      expect(expander.composite_glyphs).to eq([])
    end

    it "returns list of composite glyph names" do
      # Add multiple seac composites
      charstrings.instance_variable_set(:@charstrings, {
                                          "Agrave" => create_seac_charstring(
                                            100, 200, 50, 65, 96
                                          ),
                                          "Eacute" => create_seac_charstring(
                                            100, 200, 30, 69, 39
                                          ),
                                          "B" => create_charstring([:hsbw, 100,
                                                                    0, :endchar]),
                                        })

      composites = expander.composite_glyphs
      expect(composites).to include("Agrave", "Eacute")
      expect(composites).not_to include("B")
    end
  end

  describe "#transform_commands" do
    let(:commands) do
      [
        { type: :move_to, x: 100, y: 0 },
        { type: :line_to, x: 200, y: 100 },
        { type: :quad_to, cx: 150, cy: 50, x: 200, y: 100 },
        { type: :curve_to, cx1: 120, cy1: 30, cx2: 180, cy2: 70, x: 200,
          y: 100 },
        { type: :close_path },
      ]
    end

    it "applies translation to move_to commands" do
      result = expander.send(:transform_commands, commands, 10, 20)
      move_cmd = result.find { |c| c[:type] == :move_to }
      expect(move_cmd[:x]).to eq(110)  # 100 + 10
      expect(move_cmd[:y]).to eq(20)   # 0 + 20
    end

    it "applies translation to line_to commands" do
      result = expander.send(:transform_commands, commands, 10, 20)
      line_cmd = result.find { |c| c[:type] == :line_to }
      expect(line_cmd[:x]).to eq(210)  # 200 + 10
      expect(line_cmd[:y]).to eq(120)  # 100 + 20
    end

    it "applies translation to quad_to commands" do
      result = expander.send(:transform_commands, commands, 10, 20)
      quad_cmd = result.find { |c| c[:type] == :quad_to }
      expect(quad_cmd[:cx]).to eq(160)  # 150 + 10
      expect(quad_cmd[:cy]).to eq(70)   # 50 + 20
      expect(quad_cmd[:x]).to eq(210)   # 200 + 10
      expect(quad_cmd[:y]).to eq(120)   # 100 + 20
    end

    it "preserves close_path commands" do
      result = expander.send(:transform_commands, commands, 10, 20)
      close_cmd = result.find { |c| c[:type] == :close_path }
      expect(close_cmd).not_to be_nil
    end

    it "returns original commands when offset is zero" do
      result = expander.send(:transform_commands, commands, 0, 0)
      expect(result).to eq(commands)
    end
  end

  describe "#merge_outline_commands" do
    let(:base_commands) do
      [
        { type: :move_to, x: 100, y: 0 },
        { type: :line_to, x: 200, y: 100 },
        { type: :line_to, x: 100, y: 200 },
        { type: :close_path },
      ]
    end

    let(:accent_commands) do
      [
        { type: :move_to, x: 120, y: 80 },
        { type: :line_to, x: 150, y: 120 },
        { type: :close_path },
      ]
    end

    it "merges base and accent commands" do
      result = expander.send(:merge_outline_commands, base_commands,
                             accent_commands)

      # Base commands (without final close_path)
      expect(result[0..2]).to eq(base_commands[0..2])

      # Accent commands
      expect(result[3..5]).to eq(accent_commands)
    end

    it "removes close_path from base before merging" do
      result = expander.send(:merge_outline_commands, base_commands,
                             accent_commands)

      # The merged result should not have the base's close_path in the middle
      expect(result[2][:type]).not_to eq(:close_path)
    end
  end

  # Helper methods

  def create_charstring(commands)
    # Create a simple Type 1 CharString bytecode from command list
    charstring = String.new(encoding: Encoding::ASCII_8BIT)

    commands.each do |cmd|
      case cmd
      when :hsbw
        # hsbw x0 sbw: x0 (encoded) sbw (encoded) 12 34 (hsbw operator)
        # Note: hsbw is a two-byte operator: 12 34
        charstring << encode_number(cmd[1])  # x0
        charstring << encode_number(cmd[2])  # sbw (side bearing)
        charstring << 12  # First byte of two-byte operator
        charstring << 34  # Second byte - hsbw
      when :rmoveto
        # rmoveto: dx (encoded) dy (encoded) 21 (rmoveto operator)
        charstring << encode_number(cmd[1])  # dx
        charstring << encode_number(cmd[2])  # dy
        charstring << 21 # rmoveto
      when :hmoveto
        # hmoveto: dx (encoded) 22 (hmoveto operator)
        charstring << encode_number(cmd[1]) # dx
        charstring << 22 # hmoveto
      when :vmoveto
        # vmoveto: dy (encoded) 4 (vmoveto operator)
        charstring << encode_number(cmd[1]) # dy
        charstring << 4 # vmoveto
      when :rlineto
        # rlineto: dx (encoded) dy (encoded) 5 (rlineto operator)
        charstring << encode_number(cmd[1])  # dx
        charstring << encode_number(cmd[2])  # dy
        charstring << 5 # rlineto
      when :endchar
        # endchar: 14
        charstring << 14
      end
    end

    charstring
  end

  def create_seac_charstring(asb, adx, ady, bchar, achar)
    # Create a seac CharString: seac asb adx ady bchar achar
    # Operator 12, 6 is seac (two-byte operator)
    charstring = String.new(encoding: Encoding::ASCII_8BIT)

    # Push numbers onto stack
    charstring << encode_number(asb)
    charstring << encode_number(adx)
    charstring << encode_number(ady)
    charstring << encode_number(bchar)
    charstring << encode_number(achar)

    # seac operator (12, 6)
    charstring << 12
    charstring << 6

    charstring
  end

  def encode_number(num)
    num = num.to_i if num.is_a?(String)
    if num >= -107 && num <= 107
      [num + 139].pack("C")
    else
      num += 32768 if num < 0
      [255, num % 256, num >> 8].pack("C*")
    end
  end
end
