# frozen_string_literal: true

# Autoload hub for the Fontisan::Optimizers namespace.

module Fontisan
  module Optimizers
    autoload :CharstringRewriter, "fontisan/optimizers/charstring_rewriter"
    autoload :PatternAnalyzer, "fontisan/optimizers/pattern_analyzer"
    autoload :StackTracker, "fontisan/optimizers/stack_tracker"
    autoload :SubroutineBuilder, "fontisan/optimizers/subroutine_builder"
    autoload :SubroutineGenerator, "fontisan/optimizers/subroutine_generator"
    autoload :SubroutineOptimizer, "fontisan/optimizers/subroutine_optimizer"
  end
end
