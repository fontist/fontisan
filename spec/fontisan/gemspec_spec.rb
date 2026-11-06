# frozen_string_literal: true

RSpec.describe "fontisan.gemspec" do # rubocop:disable RSpec/DescribeClass
  let(:spec) { Gem::Specification.load(File.expand_path("../../fontisan.gemspec", __dir__)) }

  it "keeps ffi an optional dependency (only platform gems carry the cdylib)" do
    expect(spec.runtime_dependencies.map(&:name)).not_to include("ffi")
  end

  it "builds the native extension from source only through the no-op-safe extconf" do
    expect(spec.extensions).to eq(["ext/fontisan_native/extconf.rb"])
  end

  it "leaves the corpus fixtures out of the gem" do
    expect(spec.files.grep(%r{\Acorpus/})).to be_empty
  end

  it "loads the per-Ruby-minor extension of a platform gem first" do
    expect(Fontisan::Native::VERSIONED_EXTENSION)
      .to eq("fontisan/native/#{RUBY_VERSION[/\A\d+\.\d+/]}/fontisan_native")
  end
end
