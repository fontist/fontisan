# frozen_string_literal: true

module Fontisan
  module Audit
    module Extractors
      # Abstract extractor interface. Subclasses implement `#extract`.
      #
      # An extractor reads from a Context and returns a hash of fields
      # suitable for `Models::Audit::AuditReport.new(**fields)`.
      # Returning an empty hash is valid (no-op).
      class Base
        def extract(context)
          raise NotImplementedError,
                "#{self.class} must implement #extract"
        end

        protected

        # Convenience accessor used by most extractors.
        def font(context)
          context.font
        end
      end
    end
  end
end
