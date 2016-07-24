# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'gitexplorer/version'

Gem::Specification.new do |spec|
  spec.name          = "git_explorer"
  spec.version       = GitExplorer::VERSION
  spec.authors       = ["Alex Rocha"]
  spec.email         = ["alex.rochas@yahoo.com.br"]

  spec.summary       = "Local git repo explorer"
  spec.description   = "Will explore and return information about all your git repo"
  spec.homepage      = "https://github.com/alexrochas/git-explorer"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.12"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_dependency "thor", "~> 0.19.1"
end
