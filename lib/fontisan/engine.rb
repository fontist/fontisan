# frozen_string_literal: true

module Fontisan
  # Engine selection for the {Fontisan::Reference} operations.
  #
  #   FONTISAN_ENGINE=ruby|native|ffi|auto   (default auto)
  #   FONTISAN_ENGINE_STRICT=1               (no fallback)
  #
  # `auto` resolves native, then ffi, then ruby: the first tier that is
  # available and supports the operation wins. A forced tier that is unavailable
  # falls back to Ruby silently, or raises {TierUnavailable} at setup when
  # strict. An operation (or a path, e.g. dfont) a tier cannot serve always goes to
  # Ruby, strict or not. FONTISAN_MODE and FONTISAN_LAZY are not read here.
  #
  # The Ruby tier is the unmodified Reference implementation; the gate is a
  # module prepended to Reference's singleton, so Reference bodies are
  # untouched. Its output is unchanged (no served_by key), so goldens stay
  # tier-independent; {Engine.scan} and {Engine.audit_dir} return the same
  # rows with a per-row "served_by".
  module Engine
    class Error < Fontisan::Error; end
    class ConfigError < Error; end
    class TierUnavailable < Error; end
    # A WOFF2 operation fell to the Ruby tier on a platform with no `brotli`.
    class Woff2Unavailable < TierUnavailable; end

    SELECTIONS = %w[ruby native ffi auto].freeze
    AUTO_ORDER = %i[native ffi ruby].freeze
    OPS = %i[read outline_hashes audit audit_dir scan convert extract
             instance glyph_ids subset].freeze
    REPLACEABLE_TIERS = %i[native ffi].freeze
    TIER_CONTRACT = %i[available? supports? call].freeze
    ROW_RECORDER = :fontisan_engine_rows
    IN_OPERATION = :fontisan_engine_in_operation

    Config = Struct.new(:selection, :strict)

    # The Ruby tier: the original Reference methods, captured before the
    # gate is prepended.
    class RubyTier
      def initialize(originals)
        @originals = originals
      end

      def available?
        true
      end

      def supports?(_operation, _path = nil)
        true
      end

      def call(operation, ...)
        @originals.fetch(operation).call(...)
      end
    end

    # Prepended to Reference's singleton: one gate per Reference operation.
    module Gate
      OPS.each do |operation|
        define_method(operation) do |*args, **kwargs, &block|
          Engine.dispatch(operation, args, kwargs, &block)
        end
      end
    end

    @mutex = Mutex.new
    @tiers = nil
    @served = {}
    @counters = nil
    @availability = {}

    class << self
      # Prepend the gates onto +reference+ (once).
      def install(reference)
        return if reference.singleton_class.include?(Gate)

        originals = OPS.to_h { |operation| [operation, reference.method(operation)] }
        @tiers = { ruby: RubyTier.new(originals) }.freeze
        reference.singleton_class.prepend(Gate)
      end

      # Current configuration from the environment; raises at setup for a
      # bad value or a strict forced tier that is not available.
      def setup!
        # The gates are installed when Reference loads (autoload); a fresh
        # process, e.g. the CLI, reaches the engine before anything touched it.
        Fontisan::Reference unless @tiers
        config = config_from_env
        return config unless config.strict && forced?(config.selection)

        tier = config.selection
        unless available?(tier)
          raise TierUnavailable,
                "FONTISAN_ENGINE=#{tier} with FONTISAN_ENGINE_STRICT=1 " \
                "but the #{tier} tier is not available"
        end
        config
      end

      # Tier (Symbol) that serves +operation+ for +path+ under the current config.
      def resolve(operation, path = nil, options = nil)
        config = setup!
        tier = candidates(config).find do |name|
          available?(name) && supports?(name, operation, path, options)
        end || :ruby
        require_woff2_support!(operation, path, options) if tier == :ruby
        tier
      end

      # Tier that served the last call of +operation+ in this process; nil if none.
      def served_by(operation)
        @mutex.synchronize { @served[operation.to_sym] }
      end

      # { tier => { operation => calls } } since the last {reset!}.
      def counters
        @mutex.synchronize do
          (@counters || {}).transform_values(&:dup)
        end
      end

      # Scan rows with a "served_by" tier name per row.
      def scan(paths)
        scan_pairs(paths).flat_map do |tier, rows|
          rows.map { |row| row.merge("served_by" => tier.to_s) }
        end
      end

      # audit_dir entries with a "served_by" tier name per entry: the tier
      # that audited that file. A file the serving tier hands back to Ruby
      # (dfont, Type 1 inside a native audit_dir) is recorded as :ruby by the
      # nested call; every other entry carries the tier that served the call.
      def audit_dir(dir, validate: false)
        dir_path = File.path(dir)
        whole = resolve(:audit_dir, dir_path)
        seen = {}
        entries = with_recorder(seen) do
          Reference.audit_dir(dir, validate: validate)
        end
        entries.map do |entry|
          tier = seen[File.join(dir_path, entry["path"])] || whole
          entry.merge("served_by" => tier.to_s)
        end
      end

      # Run +operation+ on the Ruby tier, whatever is selected (a tier handing
      # a file it cannot read back to Ruby).
      def ruby_call(operation, ...)
        tier_object(:ruby).call(operation, ...)
      end

      # Called by the gates.
      def dispatch(operation, args, kwargs, &)
        path = args.first
        path = path.to_s if path.respond_to?(:to_path)
        path = nil unless path.is_a?(String)
        return scan_rows(args, kwargs) if operation == :scan && !args.empty?

        tier = resolve(operation, path, kwargs)
        run(tier, operation, path, args, kwargs, &)
      end

      # The object-based entry points (`Subset::Builder.new(font, ...)`,
      # `Variable::Instancer.new(font)`) are never dispatched: a loaded font's
      # state lives in cached parsed tables, so they always run on Ruby. They
      # call this so that {served_by} reports it; inside a gated call (the
      # Ruby tier's own Reference body) the gate has already recorded the tier.
      def record_ruby(operation)
        return if Thread.current[IN_OPERATION]

        record(:ruby, operation, nil)
      end

      # Forget probes, counters, served state and registered tiers.
      def reset!
        @mutex.synchronize do
          @served = {}
          @counters = nil
          @availability = {}
          @tiers = @tiers.slice(:ruby) if @tiers
        end
        Native.reset!
        Ffi.reset!
      end

      # Register a tier object (tests, or the extension itself). A bad
      # registration raises here, at setup, never as a silent fallback later.
      def register(name, tier)
        validate_registration!(name, tier)
        @mutex.synchronize do
          @tiers = @tiers.merge(name.to_sym => tier).freeze
          @availability.delete(name.to_sym)
        end
      end

      private

      def validate_registration!(name, tier)
        unless REPLACEABLE_TIERS.include?(name.to_s.to_sym)
          raise ConfigError,
                "cannot register tier #{name.inspect}: only " \
                "#{REPLACEABLE_TIERS.join(' and ')} can be registered"
        end

        missing = TIER_CONTRACT.reject { |method| tier.respond_to?(method) }
        return if missing.empty?

        raise ConfigError,
              "tier #{name} does not implement #{missing.join(', ')}"
      end

      def config_from_env
        selection = ENV.fetch("FONTISAN_ENGINE", "auto").strip.downcase
        selection = "auto" if selection.empty?
        unless SELECTIONS.include?(selection)
          raise ConfigError,
                "FONTISAN_ENGINE=#{selection.inspect} is not one of " \
                "#{SELECTIONS.join(', ')}"
        end

        strict = %w[1 true yes on].include?(
          ENV.fetch("FONTISAN_ENGINE_STRICT", "").strip.downcase,
        )
        Config.new(selection.to_sym, strict)
      end

      # The java-platform gem has no `brotli`: a WOFF2 operation that no other
      # tier took must fail here, at setup, not as a LoadError mid-parse.
      def require_woff2_support!(operation, path, options)
        return unless woff2_operation?(path, options)
        return if Utilities::BrotliWrapper.available?

        raise Woff2Unavailable,
              "#{operation} on WOFF2 needs the ffi tier or the `brotli` gem; " \
              "neither is available. #{Utilities::BrotliWrapper::MISSING_MESSAGE}"
      end

      def woff2_operation?(path, options)
        File.extname(path.to_s).casecmp?(".woff2") ||
          options&.dig(:to).to_s.casecmp?("woff2")
      end

      def forced?(selection)
        %i[native ffi].include?(selection)
      end

      def candidates(config)
        case config.selection
        when :auto then AUTO_ORDER
        when :ruby then [:ruby]
        else [config.selection]
        end
      end

      def tier_object(name)
        case name
        when :ruby then @tiers.fetch(:ruby)
        else @tiers[name] || { native: Native, ffi: Ffi }.fetch(name)
        end
      end

      def available?(name)
        @mutex.synchronize do
          return @availability[name] if @availability.key?(name)
        end
        result = probe(name)
        @mutex.synchronize { @availability[name] = result }
      end

      # Any failure while probing is "not available"; never an exception.
      def probe(name)
        tier_object(name).available? || false
      rescue StandardError, ScriptError
        false
      end

      # A tier may also vet the call's keyword options (`supports_options?`).
      def supports?(name, operation, path, options = nil)
        tier = tier_object(name)
        return false unless tier.supports?(operation, path)
        return true unless options && tier.respond_to?(:supports_options?)

        takes_path = tier.method(:supports_options?).arity.abs > 2
        (takes_path ? tier.supports_options?(operation, options, path) : tier.supports_options?(operation, options)) || false
      rescue StandardError, ScriptError
        false
      end

      def run(tier, operation, path, args, kwargs, &)
        record(tier, operation, path)
        previous = Thread.current[IN_OPERATION]
        Thread.current[IN_OPERATION] = true
        begin
          tier_object(tier).call(operation, *args, **kwargs, &)
        ensure
          Thread.current[IN_OPERATION] = previous
        end
      end

      def record(tier, operation, path)
        @mutex.synchronize do
          @served[operation] = tier
          table = (@counters ||= Hash.new { |h, k| h[k] = Hash.new(0) })
          table[tier][operation] += 1
        end
        recorder = Thread.current[ROW_RECORDER]
        recorder[path] = tier if recorder && path
      end

      def scan_rows(args, kwargs)
        raise ArgumentError, "scan takes the paths only" unless kwargs.empty?

        setup!

        scan_pairs(*args).flat_map { |_tier, rows| rows }
      end

      # [[tier, rows], ...] one pair per path, in input order.
      def scan_pairs(paths)
        Array(paths).map do |path|
          path_s = path.respond_to?(:to_path) ? path.to_path : path
          tier = resolve(:scan, path_s.is_a?(String) ? path_s : nil)
          record(tier, :scan, nil)
          [tier, tier_object(tier).call(:scan, [path]).to_a]
        end
      end

      def with_recorder(seen)
        previous = Thread.current[ROW_RECORDER]
        Thread.current[ROW_RECORDER] = seen
        yield
      ensure
        Thread.current[ROW_RECORDER] = previous
      end
    end
  end
end
