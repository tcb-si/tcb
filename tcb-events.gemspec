# frozen_string_literal: true

require_relative "lib/tcb-events"

Gem::Specification.new do |spec|
  spec.name = "tcb-events"
  spec.version = TCB::Events::VERSION
  spec.authors = ["Ljubomir Marković"]
  spec.email = ["ljubomir@tcb.si"]

  spec.summary = "The humble event bus"
  spec.description = "A simple, thread-safe event bus for Ruby applications using pub/sub pattern"
  spec.homepage = "https://github.com/tcb/tcb-events"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.glob("lib/**/*") + ["README.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  # Development dependencies
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
