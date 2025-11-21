# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    module Ttx
      module Tables
        # Panose classification in OS/2 table
        class Panose < Lutaml::Model::Serializable
          attribute :b_family_type, :integer
          attribute :b_serif_style, :integer
          attribute :b_weight, :integer
          attribute :b_proportion, :integer
          attribute :b_contrast, :integer
          attribute :b_stroke_variation, :integer
          attribute :b_arm_style, :integer
          attribute :b_letter_form, :integer
          attribute :b_midline, :integer
          attribute :b_x_height, :integer

          xml do
            root "panose"

            map_element "bFamilyType", to: :b_family_type,
                                       render_default: true
            map_element "bSerifStyle", to: :b_serif_style,
                                       render_default: true
            map_element "bWeight", to: :b_weight,
                                   render_default: true
            map_element "bProportion", to: :b_proportion,
                                       render_default: true
            map_element "bContrast", to: :b_contrast,
                                     render_default: true
            map_element "bStrokeVariation", to: :b_stroke_variation,
                                            render_default: true
            map_element "bArmStyle", to: :b_arm_style,
                                     render_default: true
            map_element "bLetterForm", to: :b_letter_form,
                                       render_default: true
            map_element "bMidline", to: :b_midline,
                                    render_default: true
            map_element "bXHeight", to: :b_x_height,
                                    render_default: true
          end
        end

        # Os2Table represents the 'OS/2' table in TTX format
        #
        # Contains OS/2 and Windows-specific metrics following the
        # OpenType specification for the OS/2 table.
        class Os2Table < Lutaml::Model::Serializable
          attribute :version, :integer
          attribute :x_avg_char_width, :integer
          attribute :us_weight_class, :integer
          attribute :us_width_class, :integer
          attribute :fs_type, :string
          attribute :y_subscript_x_size, :integer
          attribute :y_subscript_y_size, :integer
          attribute :y_subscript_x_offset, :integer
          attribute :y_subscript_y_offset, :integer
          attribute :y_superscript_x_size, :integer
          attribute :y_superscript_y_size, :integer
          attribute :y_superscript_x_offset, :integer
          attribute :y_superscript_y_offset, :integer
          attribute :y_strikeout_size, :integer
          attribute :y_strikeout_position, :integer
          attribute :s_family_class, :integer
          attribute :panose, Panose
          attribute :ul_unicode_range_1, :string
          attribute :ul_unicode_range_2, :string
          attribute :ul_unicode_range_3, :string
          attribute :ul_unicode_range_4, :string
          attribute :ach_vend_id, :string
          attribute :fs_selection, :string
          attribute :us_first_char_index, :integer
          attribute :us_last_char_index, :integer
          attribute :s_typo_ascender, :integer
          attribute :s_typo_descender, :integer
          attribute :s_typo_line_gap, :integer
          attribute :us_win_ascent, :integer
          attribute :us_win_descent, :integer
          attribute :ul_code_page_range_1, :string
          attribute :ul_code_page_range_2, :string

          xml do
            root "OS_2"

            map_element "version", to: :version,
                                   render_default: true
            map_element "xAvgCharWidth", to: :x_avg_char_width,
                                         render_default: true
            map_element "usWeightClass", to: :us_weight_class,
                                         render_default: true
            map_element "usWidthClass", to: :us_width_class,
                                        render_default: true
            map_element "fsType", to: :fs_type,
                                  render_default: true
            map_element "ySubscriptXSize", to: :y_subscript_x_size,
                                           render_default: true
            map_element "ySubscriptYSize", to: :y_subscript_y_size,
                                           render_default: true
            map_element "ySubscriptXOffset", to: :y_subscript_x_offset,
                                             render_default: true
            map_element "ySubscriptYOffset", to: :y_subscript_y_offset,
                                             render_default: true
            map_element "ySuperscriptXSize", to: :y_superscript_x_size,
                                             render_default: true
            map_element "ySuperscriptYSize", to: :y_superscript_y_size,
                                             render_default: true
            map_element "ySuperscriptXOffset", to: :y_superscript_x_offset,
                                               render_default: true
            map_element "ySuperscriptYOffset", to: :y_superscript_y_offset,
                                               render_default: true
            map_element "yStrikeoutSize", to: :y_strikeout_size,
                                          render_default: true
            map_element "yStrikeoutPosition", to: :y_strikeout_position,
                                              render_default: true
            map_element "sFamilyClass", to: :s_family_class,
                                        render_default: true
            map_element "panose", to: :panose
            map_element "ulUnicodeRange1", to: :ul_unicode_range_1,
                                           render_default: true
            map_element "ulUnicodeRange2", to: :ul_unicode_range_2,
                                           render_default: true
            map_element "ulUnicodeRange3", to: :ul_unicode_range_3,
                                           render_default: true
            map_element "ulUnicodeRange4", to: :ul_unicode_range_4,
                                           render_default: true
            map_element "achVendID", to: :ach_vend_id,
                                     render_default: true
            map_element "fsSelection", to: :fs_selection,
                                       render_default: true
            map_element "usFirstCharIndex", to: :us_first_char_index,
                                            render_default: true
            map_element "usLastCharIndex", to: :us_last_char_index,
                                           render_default: true
            map_element "sTypoAscender", to: :s_typo_ascender,
                                         render_default: true
            map_element "sTypoDescender", to: :s_typo_descender,
                                          render_default: true
            map_element "sTypoLineGap", to: :s_typo_line_gap,
                                        render_default: true
            map_element "usWinAscent", to: :us_win_ascent,
                                       render_default: true
            map_element "usWinDescent", to: :us_win_descent,
                                        render_default: true
            map_element "ulCodePageRange1", to: :ul_code_page_range_1,
                                            render_default: true
            map_element "ulCodePageRange2", to: :ul_code_page_range_2,
                                            render_default: true
          end
        end
      end
    end
  end
end
