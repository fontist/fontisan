# frozen_string_literal: true

# Autoload hub for the Fontisan::Hints namespace.

module Fontisan
  module Hints
    autoload :HintConverter, "fontisan/hints/hint_converter"
    autoload :HintValidator, "fontisan/hints/hint_validator"
    autoload :PostScriptHintApplier, "fontisan/hints/postscript_hint_applier"
    autoload :PostScriptHintExtractor, "fontisan/hints/postscript_hint_extractor"
    autoload :TrueTypeHintApplier, "fontisan/hints/truetype_hint_applier"
    autoload :TrueTypeHintExtractor, "fontisan/hints/truetype_hint_extractor"
    autoload :TrueTypeInstructionAnalyzer, "fontisan/hints/truetype_instruction_analyzer"
    autoload :TrueTypeInstructionGenerator, "fontisan/hints/truetype_instruction_generator"
  end
end
