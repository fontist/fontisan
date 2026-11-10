# frozen_string_literal: true

# Child process for the scan peak-RSS measurement: scans every file of the
# corpus fonts directory once. Usage: ruby -I<lib> scan_child.rb CORPUS_DIR
require "fontisan"

paths = Dir.glob(File.join(ARGV.fetch(0), "fonts", "**", "*")).select { |f| File.file?(f) }.sort
Fontisan::Reference.scan(paths)
