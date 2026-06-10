# frozen_string_literal: true

require_relative "lib/pagecord_cli/version"

Gem::Specification.new do |spec|
  spec.name = "pagecord-cli"
  spec.version = PagecordCLI::VERSION
  spec.authors = [ "Olly Headey" ]
  spec.email = [ "olly@pagecord.com" ]

  spec.summary = "Publish local files to Pagecord"
  spec.homepage = "https://pagecord.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/lylo/pagecord-cli"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "bin/*", "README.md", "LICENSE*"]
  end
  spec.bindir = "bin"
  spec.executables = [ "pagecord" ]
  spec.require_paths = [ "lib" ]
end
