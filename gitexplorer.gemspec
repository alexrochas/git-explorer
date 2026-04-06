lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "git_explorer/version"

Gem::Specification.new do |spec|
  spec.name = "git_explorer"
  spec.version = GitExplorer::VERSION
  spec.authors = ["Alex Rocha"]
  spec.email = ["alex.rochas@yahoo.com.br"]

  spec.summary = "Explore local git repositories and render prompt-friendly repository metadata"
  spec.description = "Scans local git repositories and reports branch, sync, status, and ownership details with configurable CLI output."
  spec.homepage = "https://github.com/alexrochas/git-explorer"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir = "bin"
  spec.executables = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"

  spec.add_development_dependency "bundler", "~> 2.5"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.13"
end
