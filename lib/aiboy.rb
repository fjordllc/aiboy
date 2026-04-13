# frozen_string_literal: true

require 'rubyboy'
require_relative 'aiboy/version'
require_relative 'aiboy/ai_interface'
require_relative 'aiboy/extensions'
require_relative 'aiboy/http_server'
require_relative 'aiboy/binary_server'

module Aiboy
  # Convenience aliases so user code can reference Aiboy::Emulator /
  # Aiboy::EmulatorHeadless without caring that the emulator itself lives
  # in the rubyboy gem. These are the same classes, reopened by
  # Aiboy::EmulatorExtensions to add #step_frame and the AiInterface mixin.
  Emulator = Rubyboy::Emulator
  EmulatorHeadless = Rubyboy::EmulatorHeadless
end
