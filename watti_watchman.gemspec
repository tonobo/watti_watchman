# frozen_string_literal: true

require_relative "lib/watti_watchman/version"

Gem::Specification.new do |spec|
  spec.name = "watti_watchman"
  spec.version = WattiWatchman::VERSION
  spec.authors = ["Tim Foerster"]
  spec.email = ["rubygems@moo.gl"]

  spec.summary = "Dumb power contoller for victron deviced"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = "https://github.com/tonobo/watti_watchman"
  spec.metadata["source_code_uri"] = "https://github.com/tonobo/watti_watchman"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency "mqtt"
  spec.add_dependency "rmodbus"
  spec.add_dependency "concurrent-ruby"
  spec.add_dependency "oj"
  spec.add_dependency "async"
  spec.add_dependency "json_schemer"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
