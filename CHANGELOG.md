## [1.0.0] - 2026-04-13

Initial release.

- `Aiboy::AiInterface` — mixin included into `Rubyboy::Emulator` and `Rubyboy::EmulatorHeadless`:
  - `#read_byte(addr)` / `#read_bytes(addr, length)` — read arbitrary bytes from the emulated memory bus
  - `#press(buttons)` — replace the currently held button set
  - `#hold(buttons)` — add to the currently held button set without releasing others
  - `#release(buttons)` — release specific buttons from the held set
  - `#release_all` — release every button
  - `#framebuffer` — the current 160×144 pixel buffer as a flat Array (SDL_PIXELFORMAT_ABGR8888)
- `#step_frame` added to both rubyboy emulator classes via `lib/aiboy/extensions.rb`. Advances exactly one rendered frame without polling the keyboard, so button state is driven entirely through `AiInterface`. On `Rubyboy::Emulator` also exposes `#window_should_close?` and `#close_window` for caller-side window management.
- `Aiboy::Emulator` and `Aiboy::EmulatorHeadless` are constant aliases for the corresponding rubyboy classes, so user code can `require 'aiboy'; emu = Aiboy::EmulatorHeadless.new(rom)` without caring that the emulator itself lives in the rubyboy gem.
- `Aiboy::BinaryServer` — fast length-prefixed binary protocol over TCP (default port 9877). Opcodes: PING / VERSION / STEP / READ_BYTE / READ_BYTES / PRESS / HOLD / RELEASE / RELEASE_ALL / FRAMEBUFFER / QUIT. Sets `TCP_NODELAY` server-side so small request/response frames are not held up by Nagle + delayed-ACK (which otherwise pins throughput at ~24 ops/sec). Benchmarks on localhost: 45k ops/sec PING, 44k ops/sec READ_BYTE, 1.4k ops/sec FRAMEBUFFER.
- `Aiboy::HttpServer` — human-friendly HTTP/JSON interface over the same operations (default port 9876). CORS wildcard enabled for browser-based dev.
- `exe/aiboy-server` — CLI that boots the emulator and starts either server. `--protocol binary` (default) or `--protocol http`, with `--visible` to also open an SDL window alongside the server.
