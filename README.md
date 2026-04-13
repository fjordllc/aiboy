# Aiboy

A programmable interface for AI agents on top of the [rubyboy](https://github.com/sacckey/rubyboy) Game Boy emulator.

Aiboy is a thin wrapper gem that **requires rubyboy** and reopens `Rubyboy::Emulator` / `Rubyboy::EmulatorHeadless` to add an agent-friendly API:

- Step the emulator one rendered frame at a time without polling the keyboard
- Read arbitrary bytes from the emulated memory bus
- Drive the joypad programmatically (press / hold / release)
- Grab the 160×144 framebuffer as pixels

All CPU / PPU / APU / cartridge logic is provided entirely by rubyboy. For the underlying emulator's features (interactive keyboard play, ROM compatibility, WASM build, keybindings, etc.) see the [rubyboy README](https://github.com/sacckey/rubyboy#readme).

## Install

```sh
gem install aiboy
```

This also installs `rubyboy` as a dependency.

## What Aiboy adds

- **`Aiboy::AiInterface`** ([`lib/aiboy/ai_interface.rb`](./lib/aiboy/ai_interface.rb)) — a mixin included into `Rubyboy::Emulator` and `Rubyboy::EmulatorHeadless`. Methods: `#read_byte` / `#read_bytes`, `#press` / `#hold` / `#release` / `#release_all`, `#framebuffer`.
- **`#step_frame`** — added to both rubyboy emulator classes. Advances exactly one rendered frame without polling the keyboard, so button state comes entirely from the AiInterface methods. On `Rubyboy::Emulator` also `#window_should_close?` / `#close_window`.
- **`aiboy-server`** ([`exe/aiboy-server`](./exe/aiboy-server)) — a CLI that boots a rubyboy emulator and exposes the AiInterface operations over TCP so agents in any language can drive it:
  - **Binary protocol** (default, port `9877`) — length-prefixed frames, tens of thousands of ops/sec on localhost. See [`lib/aiboy/binary_server.rb`](./lib/aiboy/binary_server.rb).
  - **HTTP/JSON protocol** (port `9876`) — curl-friendly and CORS-enabled. See [`lib/aiboy/http_server.rb`](./lib/aiboy/http_server.rb).

`Aiboy::Emulator` and `Aiboy::EmulatorHeadless` are constant aliases for the underlying rubyboy classes, so existing code that says `Aiboy::EmulatorHeadless.new(rom)` still works.

## 30-second example

```ruby
require 'aiboy'

emu = Aiboy::EmulatorHeadless.new('path/to/game.gb')

emu.hold(%i[a])
60.times { emu.step_frame }
emu.release_all

player_x = emu.read_byte(0xD361)
pixels   = emu.framebuffer  # 23,040 Integers (ABGR8888)
```

## Driving from another language

Start `aiboy-server` and talk to it over the binary or HTTP protocol — no Ruby required on the client side.

```sh
aiboy-server path/to/game.gb                  # binary protocol on 127.0.0.1:9877 (default)
aiboy-server path/to/game.gb --protocol http  # HTTP/JSON on 127.0.0.1:9876
aiboy-server path/to/game.gb --visible        # also open an SDL window
```

### HTTP: a quick look from the shell

```sh
curl -X POST http://127.0.0.1:9876/step
curl 'http://127.0.0.1:9876/memory?addr=0xD361&length=1'
curl -X POST -H 'Content-Type: application/json' \
  -d '{"buttons":["a","right"]}' http://127.0.0.1:9876/press
curl http://127.0.0.1:9876/framebuffer.bin -o frame.bin
```

### Binary: a typical Python agent loop

```python
import socket, struct

OP_STEP, OP_READ_BYTE, OP_PRESS = 0x03, 0x04, 0x06
BTN = {"right": 0, "left": 1, "up": 2, "down": 3, "a": 4, "b": 5, "select": 6, "start": 7}

def call(sock, op, args=b""):
    payload = bytes([op]) + args
    sock.sendall(struct.pack("<I", len(payload)) + payload)
    (length,) = struct.unpack("<I", sock.recv(4))
    body = sock.recv(length)
    if body[0] != 0:
        raise RuntimeError(body[1:].decode())
    return body[1:]

with socket.create_connection(("127.0.0.1", 9877)) as sock:
    call(sock, OP_PRESS, bytes([(1 << BTN["a"]) | (1 << BTN["right"])]))
    for _ in range(60):
        call(sock, OP_STEP)
    player_x = call(sock, OP_READ_BYTE, struct.pack("<H", 0xD361))[0]
    print("player_x =", player_x)
```

The binary protocol pushes tens of thousands of ops/sec on localhost — the per-call cost is dominated by the emulator step itself. Full opcode list and button bitmask are in [`lib/aiboy/binary_server.rb`](./lib/aiboy/binary_server.rb).

## Credits

The emulator itself — CPU, PPU, APU, cartridge support — is entirely [sacckey/rubyboy](https://github.com/sacckey/rubyboy) by [sacckey](https://github.com/sacckey). Aiboy just adds the agent-facing API layer and the server CLI on top.

## Contributing

Bug reports and pull requests welcome at <https://github.com/fjordllc/aiboy>. Contributors are expected to adhere to the [code of conduct](https://github.com/fjordllc/aiboy/blob/main/CODE_OF_CONDUCT.md).

## License

MIT. See [LICENSE.txt](./LICENSE.txt).
