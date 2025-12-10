# frozen_string_literal: true

require_relative "lib/agent_pk/version"

Gem::Specification.new do |spec|
  spec.name = "agent_pk"
  spec.version = AgentPk::VERSION
  spec.authors = ["Pete Kinnecom"]
  spec.email = ["git@k7u7.com"]

  spec.summary = <<~TEXT.strip
    A small wrapper around RubyLLM that provides custom tools and methods for
    my own scripting needs
  TEXT
  spec.homepage = "https://github.com/petekinnecom/agent_pk"
  spec.license = "WTFPL"
  spec.required_ruby_version = ">= 3.0.0"
  spec.metadata["allowed_push_host"] = ""
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency("zeitwerk")
  spec.add_dependency("activerecord")
  spec.add_dependency("sqlite3")
end
