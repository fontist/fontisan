# frozen_string_literal: true

require "spec_helper"
require "prism"

# Index rule (fontisan#156): lib/ must not start processes. The check walks
# the syntax tree, so strings, comments and unrelated method names such as
# `db.exec` do not count.
RSpec.describe "lib/ process-spawning" do
  let(:violations_in) do
    lambda do |source, name = "(source)"|
      found = []
      stack = [Prism.parse(source, filepath: name).value]
      until stack.empty?
        node = stack.pop
        case node
        when Prism::CallNode
          found << "#{name}:#{node.location.start_line} #{node.name}" if spawning_call?(node)
        when Prism::XStringNode, Prism::InterpolatedXStringNode
          found << "#{name}:#{node.location.start_line} backtick/%x"
        when Prism::ConstantReadNode
          found << "#{name}:#{node.location.start_line} #{node.name}" if banned_constant?(node.name)
        end
        stack.concat(node.compact_child_nodes)
      end
      found
    end
  end

  def spawning_call?(node)
    names = %i[fork spawn exec system popen popen2 popen2e popen3 capture2
               capture2e capture3 pipeline]
    receiver = node.receiver
    bare = receiver.nil? ||
      (receiver.is_a?(Prism::ConstantReadNode) &&
        %i[Kernel IO Open3].include?(receiver.name))
    bare && names.include?(node.name)
  end

  def banned_constant?(name)
    %i[Process Open3 PTY].include?(name)
  end

  describe "the detector" do
    it "flags every spawning form" do
      [
        "fork { }", "spawn('x')", "exec('x')", "system('x')", "Kernel.system('x')",
        "Process.clock_gettime(1)", "Open3.capture2('x')", "IO.popen('x')",
        "`ls`", "%x(ls)", "`ls \#{x}`"
      ].each do |source|
        expect(violations_in.call(source)).not_to be_empty, "missed: #{source}"
      end
    end

    it "ignores strings, comments and unrelated receivers" do
      source = "# system\nx = 'fork exec'\nconn.exec('select 1')\ndef system; end\n"
      expect(violations_in.call(source)).to be_empty
    end
  end

  it "finds none in lib/" do
    files = Dir.glob(File.expand_path("../../lib/**/*.rb", __dir__))
    expect(files).not_to be_empty
    found = files.flat_map { |f| violations_in.call(File.read(f), f) }
    expect(found).to be_empty
  end
end
