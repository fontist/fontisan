# frozen_string_literal: true

require "spec_helper"
require "fontisan/audit/extractors/base"

RSpec.describe Fontisan::Audit::Extractors::Base do
  it "raises NotImplementedError on the abstract #extract" do
    expect { described_class.new.extract(nil) }
      .to raise_error(NotImplementedError, /must implement #extract/)
  end
end
