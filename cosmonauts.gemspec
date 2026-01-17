# frozen_string_literal: true

require_relative "lib/cosmo/version"

Gem::Specification.new do |s|
  s.name          = "cosmonauts"
  s.version       = Cosmo::VERSION
  s.platform      = Gem::Platform::RUBY
  s.authors       = ["Dmitry Vorotilin"]
  s.email         = ["d.vorotilin@gmail.com"]
  s.homepage      = "https://github.com/bitsbeam/cosmonauts"
  s.summary       = "Lightweight background and stream processing"
  s.description   = "Lightweight background and stream processing for Ruby"
  s.license       = "LGPL-3.0"
  s.bindir        = "bin"
  s.executables   = ["cosmo"]
  s.require_paths = ["lib"]
  s.files         = Dir["lib/**/*", "LICENSE.txt", "README.md"]
  s.metadata = {
    "homepage_uri" => "https://github.com/bitsbeam/cosmonauts",
    "bug_tracker_uri" => "https://github.com/bitsbeam/cosmonauts/issues",
    "documentation_uri" => "https://github.com/bitsbeam/cosmonauts/blob/main/README.md",
    "changelog_uri" => "https://github.com/bitsbeam/cosmonauts/blob/main/CHANGELOG.md",
    "source_code_uri" => "https://github.com/bitsbeam/cosmonauts",
    "rubygems_mfa_required" => "true"
  }

  s.required_ruby_version = ">= 3.1.0"

  s.add_dependency "logger", ">= 1.7"
  s.add_dependency "nats-pure", "~> 2.5"
end
