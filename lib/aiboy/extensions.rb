# frozen_string_literal: true

require 'rubyboy'
# `require 'rubyboy'` pulls in Rubyboy::Emulator but not the headless variant,
# so grab it explicitly before we reopen it.
require 'rubyboy/emulator_headless'
require_relative 'ai_interface'

module Aiboy
  # Reopens Rubyboy::Emulator to add an agent-friendly #step_frame (which
  # advances exactly one rendered frame without polling the keyboard) plus
  # a few window helpers, and mixes in AiInterface for memory reads,
  # button control, and framebuffer access.
  module EmulatorExtensions
    def initialize(*args, **kwargs, &)
      super
      @direction_state = 0b1111
      @action_state = 0b1111
    end

    # Advance exactly one rendered frame. Keeps the SDL window open and
    # updated, but does NOT poll the keyboard — button state is driven
    # exclusively through AiInterface (#press / #hold / #release / #release_all).
    # Returns true if the window was asked to close during this frame.
    def step_frame
      loop do
        cycles = @cpu.exec
        @timer.step(cycles)
        @audio.queue(@apu.samples) if @apu.step(cycles)
        next unless @ppu.step(cycles)

        @lcd.draw(@ppu.buffer)
        Rubyboy::SDL.PumpEvents
        return @lcd.window_should_close?
      end
    end

    def window_should_close?
      @lcd.window_should_close?
    end

    def close_window
      @lcd.close_window
    end
  end

  # Rubyboy::EmulatorHeadless keeps @bus and @joypad as locals inside
  # #initialize, so we fish them back out of @cpu after super-init. The
  # existing #step already has step-one-frame semantics; we just rename
  # it to step_frame for symmetry with Aiboy::Emulator.
  module EmulatorHeadlessExtensions
    def initialize(*args, **kwargs, &)
      super
      @bus = @cpu.instance_variable_get(:@bus)
      @joypad = @bus.instance_variable_get(:@joypad)
      @direction_state = 0b1111
      @action_state = 0b1111
    end

    def step_frame
      step
      nil
    end
  end
end

Rubyboy::Emulator.prepend(Aiboy::EmulatorExtensions)
Rubyboy::Emulator.include(Aiboy::AiInterface)
Rubyboy::EmulatorHeadless.prepend(Aiboy::EmulatorHeadlessExtensions)
Rubyboy::EmulatorHeadless.include(Aiboy::AiInterface)
