# frozen_string_literal: true

require "spec_helper"

# fontist/fontisan#159: audit_dir lists the same paths on every tier. The ffi
# tier used to include fonts below a hidden (dot) directory.
RSpec.describe "audit_dir hidden directories across tiers" do
  include TierParity

  let(:ttf) { File.expand_path("../fixtures/fonttools/TestTTF.ttf", __dir__) }

  TierParity::TIERS.each do |tier|
    it "skips fonts below a hidden directory on the #{tier} tier" do
      skip_unless_built(tier)
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p([File.join(dir, ".hid"), File.join(dir, "sub", ".deep")])
        [".hid/c.ttf", "sub/.deep/d.ttf", "sub/b.ttf", "a.ttf"].each { |rel| FileUtils.cp(ttf, File.join(dir, rel)) }
        paths = with_engine(tier) { Fontisan::Reference.audit_dir(dir).map { |row| row["path"] } }
        expect(paths).to eq(["a.ttf", "sub/b.ttf"])
      end
    end
  end
end
