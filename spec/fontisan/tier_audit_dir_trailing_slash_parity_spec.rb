# frozen_string_literal: true

require "spec_helper"

# fontist/fontisan#159: a directory given with a trailing slash yields the same
# relative paths on every tier. The Ruby tier used to return absolute paths.
RSpec.describe "audit_dir trailing slash across tiers" do
  include TierParity

  let(:ttf) { File.expand_path("../fixtures/fonttools/TestTTF.ttf", __dir__) }

  TierParity::TIERS.each do |tier|
    ["/", "//"].each do |slashes|
      it "returns relative paths for a directory ending in #{slashes.inspect} on the #{tier} tier" do
        skip_unless_built(tier)
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, "sub"))
          FileUtils.cp(ttf, File.join(dir, "a.ttf"))
          FileUtils.cp(ttf, File.join(dir, "sub", "b.ttf"))
          paths = with_engine(tier) { Fontisan::Reference.audit_dir("#{dir}#{slashes}").map { |row| row["path"] } }
          expect(paths).to eq(["a.ttf", "sub/b.ttf"])
        end
      end
    end
  end
end
