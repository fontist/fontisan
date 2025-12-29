# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fontisan::Tables::CurveConverter do
  describe ".quadratic_to_cubic" do
    context "with simple quadratic curve" do
      let(:quad) do
        { x0: 0, y0: 0, x1: 50, y1: 100, x2: 100, y2: 0 }
      end

      it "converts to exact cubic curve" do
        cubic = described_class.quadratic_to_cubic(quad)

        expect(cubic[:x0]).to eq(0)
        expect(cubic[:y0]).to eq(0)
        expect(cubic[:x3]).to eq(100)
        expect(cubic[:y3]).to eq(0)

        # Verify degree elevation formula
        # CP1 = P0 + 2/3 * (P1 - P0)
        expect(cubic[:x1]).to be_within(0.01).of(33.33)
        expect(cubic[:y1]).to be_within(0.01).of(66.67)

        # CP2 = P2 + 2/3 * (P1 - P2)
        expect(cubic[:x2]).to be_within(0.01).of(66.67)
        expect(cubic[:y2]).to be_within(0.01).of(66.67)
      end

      it "preserves start and end points" do
        cubic = described_class.quadratic_to_cubic(quad)

        expect(cubic[:x0]).to eq(quad[:x0])
        expect(cubic[:y0]).to eq(quad[:y0])
        expect(cubic[:x3]).to eq(quad[:x2])
        expect(cubic[:y3]).to eq(quad[:y2])
      end
    end

    context "with horizontal line (collinear points)" do
      let(:quad) do
        { x0: 0, y0: 50, x1: 50, y1: 50, x2: 100, y2: 50 }
      end

      it "converts to horizontal cubic line" do
        cubic = described_class.quadratic_to_cubic(quad)

        # All y-coordinates should be 50
        expect(cubic[:y0]).to eq(50)
        expect(cubic[:y1]).to be_within(0.01).of(50)
        expect(cubic[:y2]).to be_within(0.01).of(50)
        expect(cubic[:y3]).to eq(50)

        # X-coordinates should follow degree elevation
        expect(cubic[:x0]).to eq(0)
        expect(cubic[:x1]).to be_within(0.01).of(33.33)
        expect(cubic[:x2]).to be_within(0.01).of(66.67)
        expect(cubic[:x3]).to eq(100)
      end
    end

    context "with vertical line" do
      let(:quad) do
        { x0: 50, y0: 0, x1: 50, y1: 50, x2: 50, y2: 100 }
      end

      it "converts to vertical cubic line" do
        cubic = described_class.quadratic_to_cubic(quad)

        # All x-coordinates should be 50
        expect(cubic[:x0]).to eq(50)
        expect(cubic[:x1]).to be_within(0.01).of(50)
        expect(cubic[:x2]).to be_within(0.01).of(50)
        expect(cubic[:x3]).to eq(50)

        # Y-coordinates should follow degree elevation
        expect(cubic[:y0]).to eq(0)
        expect(cubic[:y1]).to be_within(0.01).of(33.33)
        expect(cubic[:y2]).to be_within(0.01).of(66.67)
        expect(cubic[:y3]).to eq(100)
      end
    end

    context "with negative coordinates" do
      let(:quad) do
        { x0: -100, y0: -100, x1: 0, y1: 100, x2: 100, y2: -100 }
      end

      it "handles negative coordinates correctly" do
        cubic = described_class.quadratic_to_cubic(quad)

        expect(cubic[:x0]).to eq(-100)
        expect(cubic[:y0]).to eq(-100)
        expect(cubic[:x3]).to eq(100)
        expect(cubic[:y3]).to eq(-100)

        expect(cubic[:x1]).to be_within(0.01).of(-33.33)
        expect(cubic[:y1]).to be_within(0.01).of(33.33)
        expect(cubic[:x2]).to be_within(0.01).of(33.33)
        expect(cubic[:y2]).to be_within(0.01).of(33.33)
      end
    end

    context "with floating point coordinates" do
      let(:quad) do
        { x0: 0.5, y0: 0.5, x1: 50.75, y1: 100.25, x2: 100.5, y2: 0.5 }
      end

      it "handles floating point precision correctly" do
        cubic = described_class.quadratic_to_cubic(quad)

        expect(cubic[:x0]).to eq(0.5)
        expect(cubic[:y0]).to eq(0.5)
        expect(cubic[:x3]).to eq(100.5)
        expect(cubic[:y3]).to eq(0.5)

        expect(cubic[:x1]).to be_within(0.01).of(34.0)
        expect(cubic[:y1]).to be_within(0.01).of(67.0)
      end
    end

    context "with invalid input" do
      it "raises ArgumentError for non-Hash input" do
        expect do
          described_class.quadratic_to_cubic([0, 0, 50, 100, 100, 0])
        end.to raise_error(ArgumentError, /quad must be Hash/)
      end

      it "raises ArgumentError for missing keys" do
        expect do
          described_class.quadratic_to_cubic({ x0: 0, y0: 0, x1: 50 })
        end.to raise_error(ArgumentError, /quad missing keys/)
      end

      it "raises ArgumentError for non-numeric values" do
        expect do
          described_class.quadratic_to_cubic({ x0: 0, y0: 0, x1: "50", y1: 100,
                                               x2: 100, y2: 0 })
        end.to raise_error(ArgumentError, /must be Numeric/)
      end
    end
  end

  describe ".cubic_to_quadratic" do
    context "with simple cubic curve" do
      let(:cubic) do
        { x0: 0, y0: 0, x1: 33, y1: 67, x2: 67, y2: 67, x3: 100, y3: 0 }
      end

      it "approximates with quadratic curves" do
        quads = described_class.cubic_to_quadratic(cubic, max_error: 0.5)

        expect(quads).to be_an(Array)
        expect(quads).not_to be_empty
        expect(quads.first).to be_a(Hash)
        expect(quads.first).to have_key(:x0)
        expect(quads.first).to have_key(:y0)
        expect(quads.first).to have_key(:x1)
        expect(quads.first).to have_key(:y1)
        expect(quads.first).to have_key(:x2)
        expect(quads.first).to have_key(:y2)
      end

      it "preserves start and end points" do
        quads = described_class.cubic_to_quadratic(cubic, max_error: 0.5)

        expect(quads.first[:x0]).to eq(cubic[:x0])
        expect(quads.first[:y0]).to eq(cubic[:y0])
        expect(quads.last[:x2]).to eq(cubic[:x3])
        expect(quads.last[:y2]).to eq(cubic[:y3])
      end

      it "stays within error tolerance" do
        quads = described_class.cubic_to_quadratic(cubic, max_error: 0.5)
        error = described_class.calculate_error(cubic, quads)

        expect(error).to be <= 0.5
      end
    end

    context "with straight line (cubic with collinear control points)" do
      let(:cubic) do
        { x0: 0, y0: 0, x1: 33, y1: 0, x2: 67, y2: 0, x3: 100, y3: 0 }
      end

      it "converts to single quadratic curve" do
        quads = described_class.cubic_to_quadratic(cubic, max_error: 0.5)

        expect(quads.length).to eq(1)
        expect(quads.first[:y0]).to eq(0)
        expect(quads.first[:y1]).to be_within(0.1).of(0)
        expect(quads.first[:y2]).to eq(0)
      end
    end

    context "with complex curve requiring subdivision" do
      let(:cubic) do
        { x0: 0, y0: 0, x1: 0, y1: 100, x2: 100, y2: 100, x3: 100, y3: 0 }
      end

      it "subdivides into multiple quadratic curves" do
        quads = described_class.cubic_to_quadratic(cubic, max_error: 0.5)

        # Complex curve should require subdivision
        expect(quads.length).to be > 1
      end

      it "maintains error within tolerance after subdivision" do
        quads = described_class.cubic_to_quadratic(cubic, max_error: 0.5)
        error = described_class.calculate_error(cubic, quads)

        expect(error).to be <= 0.5
      end

      it "creates contiguous quadratic segments" do
        quads = described_class.cubic_to_quadratic(cubic, max_error: 0.5)

        quads.each_cons(2) do |q1, q2|
          expect(q1[:x2]).to eq(q2[:x0])
          expect(q1[:y2]).to eq(q2[:y0])
        end
      end
    end

    context "with different error tolerances" do
      let(:cubic) do
        { x0: 0, y0: 0, x1: 0, y1: 100, x2: 100, y2: 100, x3: 100, y3: 0 }
      end

      it "uses fewer segments with larger tolerance" do
        quads_loose = described_class.cubic_to_quadratic(cubic, max_error: 2.0)
        quads_tight = described_class.cubic_to_quadratic(cubic, max_error: 0.1)

        expect(quads_loose.length).to be < quads_tight.length
      end

      it "respects tight error tolerance" do
        quads = described_class.cubic_to_quadratic(cubic, max_error: 0.1)
        error = described_class.calculate_error(cubic, quads)

        expect(error).to be <= 0.1
      end
    end

    context "with negative coordinates" do
      let(:cubic) do
        { x0: -100, y0: -100, x1: -50, y1: 50, x2: 50, y2: 50, x3: 100,
          y3: -100 }
      end

      it "handles negative coordinates" do
        quads = described_class.cubic_to_quadratic(cubic, max_error: 0.5)

        expect(quads.first[:x0]).to eq(-100)
        expect(quads.first[:y0]).to eq(-100)
        expect(quads.last[:x2]).to eq(100)
        expect(quads.last[:y2]).to eq(-100)
      end
    end

    context "with invalid input" do
      it "raises ArgumentError for non-Hash input" do
        expect do
          described_class.cubic_to_quadratic([0, 0, 33, 67, 67, 67, 100, 0])
        end.to raise_error(ArgumentError, /cubic must be Hash/)
      end

      it "raises ArgumentError for missing keys" do
        expect do
          described_class.cubic_to_quadratic({ x0: 0, y0: 0, x1: 33 })
        end.to raise_error(ArgumentError, /cubic missing keys/)
      end

      it "raises ArgumentError for non-numeric values" do
        expect do
          described_class.cubic_to_quadratic(
            { x0: 0, y0: 0, x1: 33, y1: 67, x2: "67", y2: 67, x3: 100, y3: 0 },
          )
        end.to raise_error(ArgumentError, /must be Numeric/)
      end

      it "raises ArgumentError for invalid max_error" do
        cubic = { x0: 0, y0: 0, x1: 33, y1: 67, x2: 67, y2: 67, x3: 100, y3: 0 }

        expect do
          described_class.cubic_to_quadratic(cubic, max_error: 0)
        end.to raise_error(ArgumentError, /max_error must be positive/)

        expect do
          described_class.cubic_to_quadratic(cubic, max_error: -1)
        end.to raise_error(ArgumentError, /max_error must be positive/)

        expect do
          described_class.cubic_to_quadratic(cubic, max_error: "0.5")
        end.to raise_error(ArgumentError, /max_error must be Numeric/)
      end
    end
  end

  describe ".calculate_error" do
    context "with matching curves" do
      let(:cubic) do
        { x0: 0, y0: 0, x1: 33.33, y1: 66.67, x2: 66.67, y2: 66.67, x3: 100,
          y3: 0 }
      end

      let(:quad) do
        { x0: 0, y0: 0, x1: 50, y1: 100, x2: 100, y2: 0 }
      end

      it "calculates small error for degree-elevated quadratic" do
        # The cubic is the exact degree elevation of the quadratic
        error = described_class.calculate_error(cubic, [quad])

        # Error should be very small (due to floating point precision)
        expect(error).to be < 1.0
      end
    end

    context "with different curves" do
      let(:cubic) do
        { x0: 0, y0: 0, x1: 0, y1: 100, x2: 100, y2: 100, x3: 100, y3: 0 }
      end

      let(:poor_quad) do
        { x0: 0, y0: 0, x1: 50, y1: 50, x2: 100, y2: 0 }
      end

      it "calculates significant error for poor approximation" do
        error = described_class.calculate_error(cubic, [poor_quad])

        expect(error).to be > 10.0
      end
    end

    context "with multiple quadratic segments" do
      let(:cubic) do
        { x0: 0, y0: 0, x1: 0, y1: 100, x2: 100, y2: 100, x3: 100, y3: 0 }
      end

      it "measures error across all segments" do
        quads = described_class.cubic_to_quadratic(cubic, max_error: 0.5)
        error = described_class.calculate_error(cubic, quads)

        expect(error).to be_a(Float)
        expect(error).to be >= 0
        expect(error).to be <= 0.5
      end
    end

    context "with invalid input" do
      let(:cubic) do
        { x0: 0, y0: 0, x1: 33, y1: 67, x2: 67, y2: 67, x3: 100, y3: 0 }
      end

      it "raises ArgumentError for invalid cubic" do
        expect do
          described_class.calculate_error({ x0: 0 },
                                          [{ x0: 0, y0: 0, x1: 50, y1: 100,
                                             x2: 100, y2: 0 }])
        end.to raise_error(ArgumentError, /cubic missing keys/)
      end

      it "raises ArgumentError for non-Array quadratics" do
        expect do
          described_class.calculate_error(cubic,
                                          { x0: 0, y0: 0, x1: 50, y1: 100,
                                            x2: 100, y2: 0 })
        end.to raise_error(ArgumentError, /quadratics must be Array/)
      end

      it "raises ArgumentError for empty quadratics" do
        expect do
          described_class.calculate_error(cubic, [])
        end.to raise_error(ArgumentError, /quadratics cannot be empty/)
      end
    end
  end

  describe ".subdivide_cubic" do
    context "at t=0.5" do
      let(:cubic) do
        { x0: 0, y0: 0, x1: 33, y1: 67, x2: 67, y2: 67, x3: 100, y3: 0 }
      end

      it "subdivides curve into two parts" do
        left, right = described_class.subdivide_cubic(cubic, 0.5)

        expect(left).to be_a(Hash)
        expect(right).to be_a(Hash)
      end

      it "preserves start point in left curve" do
        left, _right = described_class.subdivide_cubic(cubic, 0.5)

        expect(left[:x0]).to eq(cubic[:x0])
        expect(left[:y0]).to eq(cubic[:y0])
      end

      it "preserves end point in right curve" do
        _left, right = described_class.subdivide_cubic(cubic, 0.5)

        expect(right[:x3]).to eq(cubic[:x3])
        expect(right[:y3]).to eq(cubic[:y3])
      end

      it "connects left and right curves" do
        left, right = described_class.subdivide_cubic(cubic, 0.5)

        expect(left[:x3]).to eq(right[:x0])
        expect(left[:y3]).to eq(right[:y0])
      end

      it "subdivision point matches curve evaluation at t=0.5" do
        left, _right = described_class.subdivide_cubic(cubic, 0.5)
        midpoint = described_class.evaluate_cubic(cubic, 0.5)

        expect(left[:x3]).to be_within(0.01).of(midpoint[:x])
        expect(left[:y3]).to be_within(0.01).of(midpoint[:y])
      end
    end

    context "at different t values" do
      let(:cubic) do
        { x0: 0, y0: 0, x1: 33, y1: 67, x2: 67, y2: 67, x3: 100, y3: 0 }
      end

      it "subdivides at t=0.25" do
        left, right = described_class.subdivide_cubic(cubic, 0.25)

        expect(left[:x0]).to eq(cubic[:x0])
        expect(right[:x3]).to eq(cubic[:x3])
        expect(left[:x3]).to eq(right[:x0])
      end

      it "subdivides at t=0.75" do
        left, right = described_class.subdivide_cubic(cubic, 0.75)

        expect(left[:x0]).to eq(cubic[:x0])
        expect(right[:x3]).to eq(cubic[:x3])
        expect(left[:x3]).to eq(right[:x0])
      end
    end
  end

  describe ".evaluate_cubic" do
    let(:cubic) do
      { x0: 0, y0: 0, x1: 33, y1: 67, x2: 67, y2: 67, x3: 100, y3: 0 }
    end

    it "evaluates at t=0 (start point)" do
      point = described_class.evaluate_cubic(cubic, 0.0)

      expect(point[:x]).to eq(cubic[:x0])
      expect(point[:y]).to eq(cubic[:y0])
    end

    it "evaluates at t=1 (end point)" do
      point = described_class.evaluate_cubic(cubic, 1.0)

      expect(point[:x]).to be_within(0.01).of(cubic[:x3])
      expect(point[:y]).to be_within(0.01).of(cubic[:y3])
    end

    it "evaluates at t=0.5 (midpoint)" do
      point = described_class.evaluate_cubic(cubic, 0.5)

      expect(point[:x]).to be_a(Numeric)
      expect(point[:y]).to be_a(Numeric)
      expect(point[:x]).to be > cubic[:x0]
      expect(point[:x]).to be < cubic[:x3]
    end
  end

  describe ".evaluate_quadratic" do
    let(:quad) do
      { x0: 0, y0: 0, x1: 50, y1: 100, x2: 100, y2: 0 }
    end

    it "evaluates at t=0 (start point)" do
      point = described_class.evaluate_quadratic(quad, 0.0)

      expect(point[:x]).to eq(quad[:x0])
      expect(point[:y]).to eq(quad[:y0])
    end

    it "evaluates at t=1 (end point)" do
      point = described_class.evaluate_quadratic(quad, 1.0)

      expect(point[:x]).to be_within(0.01).of(quad[:x2])
      expect(point[:y]).to be_within(0.01).of(quad[:y2])
    end

    it "evaluates at t=0.5 (midpoint)" do
      point = described_class.evaluate_quadratic(quad, 0.5)

      expect(point[:x]).to be_a(Numeric)
      expect(point[:y]).to be_a(Numeric)
      expect(point[:x]).to be > quad[:x0]
      expect(point[:x]).to be < quad[:x2]
    end
  end

  describe "round-trip conversion" do
    context "quadratic -> cubic -> quadratic" do
      let(:original_quad) do
        { x0: 0, y0: 0, x1: 50, y1: 100, x2: 100, y2: 0 }
      end

      it "preserves curve shape within tolerance" do
        # Convert quadratic to cubic (exact)
        cubic = described_class.quadratic_to_cubic(original_quad)

        # Convert cubic back to quadratic (approximation)
        recovered_quads = described_class.cubic_to_quadratic(cubic,
                                                             max_error: 0.5)

        # Should result in single quadratic curve
        expect(recovered_quads.length).to eq(1)

        # Points should be close to original
        recovered = recovered_quads.first
        expect(recovered[:x0]).to eq(original_quad[:x0])
        expect(recovered[:y0]).to eq(original_quad[:y0])
        expect(recovered[:x2]).to eq(original_quad[:x2])
        expect(recovered[:y2]).to eq(original_quad[:y2])
        expect(recovered[:x1]).to be_within(5.0).of(original_quad[:x1])
        expect(recovered[:y1]).to be_within(5.0).of(original_quad[:y1])
      end
    end
  end
end
