# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in aiboy.gemspec
gemspec

# Track the local komagata/rubyboy checkout while rubyboy patches are in flight.
gem 'rubyboy', path: '../../komagata/rubyboy'

gem 'rake', '~> 13.0'

group :development, :test do
  gem 'rspec', '~> 3.12'
  gem 'rubocop', '~> 1.57'
end
