# frozen_string_literal: true

# Autoload hub for the Fontisan::Utils namespace.

module Fontisan
  module Utils
    autoload :Future, "fontisan/utils/thread_pool"
    autoload :ThreadPool, "fontisan/utils/thread_pool"
  end
end
