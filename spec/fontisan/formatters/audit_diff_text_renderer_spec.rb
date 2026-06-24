# frozen_string_literal: true

require "spec_helper"
require "fontisan/formatters"
require "fontisan/models/audit"

RSpec.describe Fontisan::Formatters::AuditDiffTextRenderer do
  def field_change(field:, left:, right:)
    Fontisan::Models::Audit::FieldChange.new(field: field, left: left, right: right)
  end

  def cp_range(first_cp:, last_cp:)
    Fontisan::Models::Audit::CodepointRange.new(first_cp: first_cp, last_cp: last_cp)
  end

  def render(diff)
    described_class.new(diff).render
  end

  it "always prints the AUDIT DIFF header and both source paths" do
    diff = Fontisan::Models::Audit::AuditDiff.new(
      left_source: "/a.ttf", right_source: "/b.ttf",
    )
    out = render(diff)
    expect(out).to include("AUDIT DIFF")
    expect(out).to include("left:  /a.ttf")
    expect(out).to include("right: /b.ttf")
  end

  it "appends '(no differences)' when the diff is empty" do
    diff = Fontisan::Models::Audit::AuditDiff.new(
      left_source: "/a.ttf", right_source: "/b.ttf",
    )
    expect(render(diff)).to include("(no differences)")
  end

  it "lists scalar field changes with arrow notation" do
    diff = Fontisan::Models::Audit::AuditDiff.new(
      left_source: "/a.ttf", right_source: "/b.ttf",
      field_changes: [
        field_change(field: "weight_class", left: "400", right: "700"),
        field_change(field: "family_name", left: "Foo", right: "Bar"),
      ]
    )
    out = render(diff)
    expect(out).to include("FIELD CHANGES (2)")
    expect(out).to include('weight_class: "400" → "700"')
    expect(out).to include('family_name: "Foo" → "Bar"')
  end

  it "renders the codepoint delta counts and previews when present" do
    delta = Fontisan::Models::Audit::CodepointSetDiff.new(
      added: [cp_range(first_cp: 0x41, last_cp: 0x5A)],
      removed: [cp_range(first_cp: 0x61, last_cp: 0x7A)],
      added_count: 26, removed_count: 26, unchanged_count: 10
    )
    diff = Fontisan::Models::Audit::AuditDiff.new(
      left_source: "/a.ttf", right_source: "/b.ttf",
      codepoints: delta
    )
    out = render(diff)
    expect(out).to include("added:      26")
    expect(out).to include("removed:    26")
    expect(out).to include("unchanged:  10")
    expect(out).to include("+ U+0041-U+005A")
    expect(out).to include("- U+0061-U+007A")
  end

  it "renders each structural change set when present" do
    diff = Fontisan::Models::Audit::AuditDiff.new(
      left_source: "/a.ttf", right_source: "/b.ttf",
      added_scripts: %w[cyrl],
      removed_features: %w[liga],
      added_blocks: ["Greek and Coptic"],
      added_languages: %w[fr]
    )
    out = render(diff)
    expect(out).to include("SCRIPTS CHANGES").and include("+ cyrl")
    expect(out).to include("FEATURES CHANGES").and include("- liga")
    expect(out).to include("BLOCKS CHANGES").and include("+ Greek and Coptic")
    expect(out).to include("LANGUAGES CHANGES").and include("+ fr")
  end

  it "omits a structural section when both sides are empty" do
    diff = Fontisan::Models::Audit::AuditDiff.new(
      left_source: "/a.ttf", right_source: "/b.ttf",
    )
    out = render(diff)
    expect(out).not_to include("SCRIPTS CHANGES")
    expect(out).not_to include("FEATURES CHANGES")
  end
end
