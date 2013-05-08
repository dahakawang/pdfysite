# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'pdfysite/version'

Gem::Specification.new do |spec|
  spec.name          = "pdfysite"
  spec.version       = Pdfysite::VERSION
  spec.authors       = ["David Wang"]
  spec.email         = ["DevilDavidWang@gmail.com"]
  spec.description   = %q{pdfysite is a tool to collect your own posts or your starred post on a website and convert them all to a pdf book.}
  spec.summary       = %q{Tool to convert websites to PDF books}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
