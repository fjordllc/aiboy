# frozen_string_literal: true

require_relative 'lib/aiboy/version'

Gem::Specification.new do |spec|
  spec.name = 'aiboy'
  spec.version = Aiboy::VERSION
  spec.authors = %w[komagata sacckey]

  spec.summary = 'A programmable interface for AI agents on top of the rubyboy Game Boy emulator'
  spec.description = <<~DESC
    Aiboy is a thin wrapper over the rubyboy gem that adds an agent-friendly interface:
    advance one frame at a time with #step_frame, read arbitrary bytes from the emulated
    memory bus, drive buttons programmatically, and grab the 160x144 framebuffer as an
    array of pixels. It also ships an aiboy-server CLI that exposes these operations over
    a fast binary TCP protocol or a human-friendly HTTP/JSON interface, so agents written
    in any language can drive the emulator. The underlying CPU/PPU/APU/cartridge
    implementation is provided entirely by rubyboy; aiboy only adds the AI interface layer.
  DESC
  spec.homepage = 'https://github.com/fjordllc/aiboy'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = 'https://github.com/fjordllc/aiboy/blob/main/CHANGELOG.md'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/fjordllc/aiboy/issues'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = %w[aiboy-server]
  spec.require_paths = ['lib']

  spec.add_dependency 'rubyboy', '~> 1.5'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
