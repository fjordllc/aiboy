# Repository Guidelines

## Project Structure & Module Organization

Aiboy is a Ruby gem that layers an agent-facing API on top of `rubyboy`.
Runtime code lives in `lib/aiboy/`, with `lib/aiboy.rb` as the gem entry point.
The server CLI is `exe/aiboy-server`; development helpers are in `bin/`.
Specs live in `spec/`, and the bundled test ROM is `lib/roms/hello-world.gb`.
Gem metadata and release settings are defined in `aiboy.gemspec`; task wiring is in
`Rakefile`.

## Build, Test, and Development Commands

- `bin/setup`: install gem dependencies for local development.
- `bin/console`: open an IRB session with the gem loaded.
- `bundle exec rake`: run the default quality gate, currently specs plus RuboCop.
- `bundle exec rspec`: run the RSpec test suite only.
- `bundle exec rubocop`: run style and lint checks.
- `bundle exec exe/aiboy-server lib/roms/hello-world.gb`: start the local binary
  server against the bundled ROM. Add `--protocol http` for HTTP/JSON.

## Coding Style & Naming Conventions

Use Ruby 3.2+ and follow the existing RuboCop configuration in `.rubocop.yml`.
All Ruby files should use `# frozen_string_literal: true`. Prefer two-space
indentation, snake_case methods and variables, PascalCase classes/modules, and
constants for protocol opcodes or fixed values. Keep the gem as a thin wrapper:
emulator CPU, PPU, APU, and cartridge behavior should remain in `rubyboy`.

## Testing Guidelines

Tests use RSpec with `expect` syntax and monkey patching disabled. Add or update
specs in `spec/` when changing public API methods, server protocols, or CLI
behavior. Name examples by behavior, for example `it 'reads a byte range on
READ_BYTES'`. Use `lib/roms/hello-world.gb` for deterministic emulator tests
instead of adding large ROM assets.

## Commit & Pull Request Guidelines

The current history uses short imperative commit messages, for example
`Add aiboy: an AI-agent interface layer on top of rubyboy`. Keep future commits
focused and describe the user-visible change. Pull requests should include a
brief summary, test results such as `bundle exec rake`, and any protocol or CLI
compatibility notes. Link related issues when available, and include screenshots
only for visible emulator or server UI changes.

## Security & Configuration Tips

Do not commit proprietary ROMs, credentials, or local `.rspec_status` changes.
The development `Gemfile` currently tracks `komagata/rubyboy` from Git; note any
dependency source changes clearly in the PR because they affect emulator
behavior and reproducibility.
