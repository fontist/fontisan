# frozen_string_literal: true

module Fontisan
  module Ufo
    # Compiler layer: turns a typed Fontisan::Ufo::Font into OpenType
    # binary tables, then into a TTF or OTF file via Fontisan::FontWriter.
    #
    # Pipeline:
    #
    #   Fontisan::Ufo::Font (typed)
    #          │
    #          ▼
    #   BaseCompiler#compile
    #     │
    #     ├─ Head.build(font)     → Tables::Head BinData record
    #     ├─ Hhea.build(font)     → Tables::Hhea
    #     ├─ Maxp.build(font)     → Tables::Maxp
    #     ├─ Os2.build(font)      → Tables::Os2
    #     ├─ Name.build(font)     → Tables::Name
    #     ├─ Post.build(font)     → Tables::Post
    #     ├─ Hmtx.build(font)     → Tables::Hmtx
    #     ├─ Cmap.build(font)     → Tables::Cmap
    #     ├─ (TTF) GlyfLoca.build → Tables::Glyf + Tables::Loca
    #     └─ (OTF) Cff.build      → Tables::Cff
    #          │
    #          ▼
    #   tables_hash.transform_values(&:to_binary_s)
    #          │
    #          ▼
    #   Fontisan::FontWriter.write_to_file(...)
    module Compile
      autoload :BaseCompiler, "fontisan/ufo/compile/base_compiler"
      autoload :TtfCompiler,  "fontisan/ufo/compile/ttf_compiler"
      autoload :OtfCompiler,  "fontisan/ufo/compile/otf_compiler"
      autoload :Filters,      "fontisan/ufo/compile/filters"
      autoload :Fvar,         "fontisan/ufo/compile/fvar"
      autoload :Gpos,         "fontisan/ufo/compile/gpos"
      autoload :Gvar,         "fontisan/ufo/compile/gvar"
      autoload :Head,         "fontisan/ufo/compile/head"
      autoload :Hhea,         "fontisan/ufo/compile/hhea"
      autoload :Maxp,         "fontisan/ufo/compile/maxp"
      autoload :Os2,          "fontisan/ufo/compile/os2"
      autoload :Name,         "fontisan/ufo/compile/name"
      autoload :Post,         "fontisan/ufo/compile/post"
      autoload :Hmtx,         "fontisan/ufo/compile/hmtx"
      autoload :Cmap,         "fontisan/ufo/compile/cmap"
      autoload :GlyfLoca,     "fontisan/ufo/compile/glyf_loca"
      autoload :Cff,          "fontisan/ufo/compile/cff"
      autoload :Cff2,         "fontisan/ufo/compile/cff2"
      autoload :Otf2Compiler, "fontisan/ufo/compile/otf2_compiler"
      autoload :Avar,         "fontisan/ufo/compile/avar"
      autoload :Hvar,         "fontisan/ufo/compile/hvar"
      autoload :Mvar,         "fontisan/ufo/compile/mvar"
      autoload :Stat,         "fontisan/ufo/compile/stat"
      autoload :VariableTtf,  "fontisan/ufo/compile/variable_ttf"
      autoload :ItemVariationStore,
               "fontisan/ufo/compile/item_variation_store"
    end
  end
end
