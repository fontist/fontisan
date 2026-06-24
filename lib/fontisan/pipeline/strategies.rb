# frozen_string_literal: true

# Autoload hub for the Fontisan::Pipeline::Strategies namespace.

module Fontisan
  module Pipeline
    module Strategies
      autoload :BaseStrategy, "fontisan/pipeline/strategies/base_strategy"
      autoload :InstanceStrategy, "fontisan/pipeline/strategies/instance_strategy"
      autoload :NamedStrategy, "fontisan/pipeline/strategies/named_strategy"
      autoload :PreserveStrategy, "fontisan/pipeline/strategies/preserve_strategy"
    end
  end
end
