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
    SPEED_RANGE = (1.0..8.0)

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

    # Current emulation speed multiplier. 1.0 is normal speed; 2.0, 4.0,
    # and 8.0 are useful for fast AI runs and shorter integration tests.
    def speed
      @speed || 1.0
    end

    # Set the emulation speed multiplier. Visible Rubyboy emulators use this
    # to adjust frame pacing; headless emulators retain the value for API
    # symmetry because they already run as fast as the host can step frames.
    # rubocop:disable Naming/AccessorMethodName
    def set_speed(speed)
      normalized = normalize_ai_speed(speed)
      apply_speed(normalized)
      normalized
    end
    # rubocop:enable Naming/AccessorMethodName

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

    def normalize_ai_speed(speed)
      normalized = Float(speed)
      raise ArgumentError, 'speed must be between 1.0 and 8.0' unless SPEED_RANGE.cover?(normalized) && normalized.finite?

      normalized
    rescue ArgumentError, TypeError
      raise ArgumentError, 'speed must be between 1.0 and 8.0'
    end

    def apply_speed(speed)
      @speed = speed
    end

    def apply_button_state(direction, action)
      @direction_state = direction
      @action_state = action
      @joypad.direction_button(direction)
      @joypad.action_button(action)
    end
  end
end
