# frozen_string_literal: true

require_relative "lib/tcb"

Gem::Specification.new do |spec|
  spec.name = "tcb"
  spec.version = TCB::VERSION
  spec.authors = ["Ljubomir Marković"]
  spec.email = ["ljubomir@tcb.si"]

  spec.summary = "Lightweight DDD runtime for Rails — events, commands, and aggregates"
  spec.description = "TCB gives Rails applications a clean domain language for DDD. Thread-safe event bus, command routing, aggregate pattern, and opt-in event persistence."
  spec.homepage = "https://github.com/tcb-si/tcb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.glob("lib/**/*") + ["README.md", "LICENSE.txt", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  # Development dependencies
  spec.add_development_dependency "railties"
  spec.add_development_dependency "activerecord"
  spec.add_development_dependency "sqlite3", "~> 2.9"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest-reporters", "~> 1.7.1"
  spec.add_development_dependency "debug", "~> 1.9.2"
  spec.add_dependency "method_source", "~> 1.0"
end
