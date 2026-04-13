# frozen_string_literal: true

module Aiboy
  # Methods that let an external caller drive the emulator like an AI agent:
  # read arbitrary memory, drive the joypad, and grab the rendered framebuffer.
  # Included by both Emulator (SDL window) and EmulatorHeadless (no window)
  # so the exact same script works against either backend.
  #
  # Host classes must expose these instance variables:
  #   @bus             — Rubyboy::Bus
  #   @ppu             — Rubyboy::Ppu
  #   @joypad          — Rubyboy::Joypad
  #   @direction_state — Integer, initialized to 0b1111 (all released)
  #   @action_state    — Integer, initialized to 0b1111
  module AiInterface
    BUTTON_BITS = {
      right: [:direction, 0],
      left: [:direction, 1],
      up: [:direction, 2],
      down: [:direction, 3],
      a: [:action, 0],
      b: [:action, 1],
      select: [:action, 2],
      start: [:action, 3]
    }.freeze

    # Read a single byte from the emulated memory bus. Routing to
    # ROM / VRAM / WRAM / OAM / HRAM / I/O registers is automatic.
    def read_byte(addr)
      @bus.read_byte(addr)
    end

    # Read `length` consecutive bytes starting at `addr`, returned as an Array.
    def read_bytes(addr, length)
      Array.new(length) { |i| @bus.read_byte(addr + i) }
    end

    # Replace the currently held button set. `buttons` is an Array of Symbols
    # from BUTTON_BITS.keys. Unspecified buttons are released.
    def press(buttons)
      direction = 0b1111
      action = 0b1111
      buttons.each do |name|
        kind, bit = BUTTON_BITS.fetch(name) { raise ArgumentError, "unknown button: #{name}" }
        if kind == :direction
          direction &= ~(1 << bit) & 0b1111
        else
          action &= ~(1 << bit) & 0b1111
        end
      end
      apply_button_state(direction, action)
    end

    # Add `buttons` to the currently held button set without releasing others.
    def hold(buttons)
      direction = @direction_state
      action = @action_state
      buttons.each do |name|
        kind, bit = BUTTON_BITS.fetch(name) { raise ArgumentError, "unknown button: #{name}" }
        if kind == :direction
          direction &= ~(1 << bit) & 0b1111
        else
          action &= ~(1 << bit) & 0b1111
        end
      end
      apply_button_state(direction, action)
    end

    # Release `buttons` from the currently held set, leaving others untouched.
    def release(buttons)
      direction = @direction_state
      action = @action_state
      buttons.each do |name|
        kind, bit = BUTTON_BITS.fetch(name) { raise ArgumentError, "unknown button: #{name}" }
        if kind == :direction
          direction |= (1 << bit) & 0b1111
        else
          action |= (1 << bit) & 0b1111
        end
      end
      apply_button_state(direction, action)
    end

    # Release every button.
    def release_all
      apply_button_state(0b1111, 0b1111)
    end

    # The current 160x144 framebuffer as a flat Array of 23,040 Integers.
    # Each pixel is a 32-bit value in SDL_PIXELFORMAT_ABGR8888:
    #
    #   R = pixel         & 0xFF
    #   G = (pixel >>  8) & 0xFF
    #   B = (pixel >> 16) & 0xFF
    #   A = (pixel >> 24) & 0xFF
    #
    # Game Boy is monochrome, so in practice only four values appear:
    # 0xFF000000 (black), 0xFF555555, 0xFFAAAAAA, 0xFFFFFFFF (white).
    # All pixels are fully opaque.
    def framebuffer
      @ppu.buffer
    end

    private

    def apply_button_state(direction, action)
      @direction_state = direction
      @action_state = action
      @joypad.direction_button(direction)
      @joypad.action_button(action)
    end
  end
end
