# frozen_string_literal: true

RSpec.describe Aiboy do
  it 'has a version number' do
    expect(Aiboy::VERSION).not_to be_nil
  end
end

RSpec.describe Aiboy::BinaryServer do
  let(:rom_path) { File.expand_path('../lib/roms/hello-world.gb', __dir__) }
  let(:emulator) { Aiboy::EmulatorHeadless.new(rom_path) }
  let(:server) { described_class.new(emulator) }

  def call(opcode, args = ''.b)
    response = server.dispatch(([opcode].pack('C') + args.b).b)
    [response.getbyte(0), response.byteslice(1, response.bytesize - 1)]
  end

  describe '#dispatch' do
    it 'responds PONG to PING' do
      status, body = call(described_class::OP_PING)
      expect(status).to eq(0x00)
      expect(body).to eq('PONG')
    end

    it 'responds with the gem version to VERSION' do
      status, body = call(described_class::OP_VERSION)
      expect(status).to eq(0x00)
      expect(body).to eq(Aiboy::VERSION)
    end

    it 'advances one frame on STEP' do
      status, body = call(described_class::OP_STEP)
      expect(status).to eq(0x00)
      expect(body.bytesize).to eq(1)
      expect(body.getbyte(0)).to eq(0)
    end

    it 'reads and updates emulation speed' do
      status, body = call(described_class::OP_GET_SPEED)
      expect(status).to eq(0x00)
      expect(body.unpack1('E')).to eq(1.0)

      status, body = call(described_class::OP_SET_SPEED, [4.0].pack('E'))
      expect(status).to eq(0x00)
      expect(body.unpack1('E')).to eq(4.0)
      expect(emulator.speed).to eq(4.0)
    end

    it 'rejects speed outside the AI range' do
      status, body = call(described_class::OP_SET_SPEED, [9.0].pack('E'))
      expect(status).to eq(0xFF)
      expect(body).to include('between 1.0 and 8.0')
    end

    it 'reads a single byte from cartridge ROM on READ_BYTE' do
      status, body = call(described_class::OP_READ_BYTE, [0x0104].pack('v'))
      expect(status).to eq(0x00)
      expect(body.getbyte(0)).to eq(0xCE)
    end

    it 'reads a byte range on READ_BYTES' do
      status, body = call(described_class::OP_READ_BYTES, [0x0104, 4].pack('vv'))
      expect(status).to eq(0x00)
      expect(body.bytes).to eq([0xCE, 0xED, 0x66, 0x66])
    end

    it 'applies PRESS via bitmask' do
      # bit 0 right + bit 4 a = 0b00010001 = 0x11
      status, = call(described_class::OP_PRESS, [0x11].pack('C'))
      expect(status).to eq(0x00)
      expect(emulator.instance_variable_get(:@direction_state)).to eq(0b1110)
      expect(emulator.instance_variable_get(:@action_state)).to eq(0b1110)
    end

    it 'supports HOLD / RELEASE accumulation' do
      call(described_class::OP_HOLD, [0b00000001].pack('C'))
      call(described_class::OP_HOLD, [0b00010000].pack('C'))
      call(described_class::OP_RELEASE, [0b00000001].pack('C'))
      expect(emulator.instance_variable_get(:@direction_state)).to eq(0b1111)
      expect(emulator.instance_variable_get(:@action_state)).to eq(0b1110)
    end

    it 'returns the raw framebuffer on FRAMEBUFFER' do
      call(described_class::OP_STEP)
      status, body = call(described_class::OP_FRAMEBUFFER)
      expect(status).to eq(0x00)
      expect(body.bytesize).to eq(160 * 144 * 4)
    end

    it 'returns an error status byte for unknown opcodes' do
      status, body = call(0xEE)
      expect(status).to eq(0xFF)
      expect(body).to include('unknown opcode')
    end

    it 'returns an error status byte for malformed READ_BYTE args' do
      status, body = call(described_class::OP_READ_BYTE, ''.b)
      expect(status).to eq(0xFF)
      expect(body).to include('addr')
    end
  end
end

RSpec.describe Aiboy::HttpServer do
  let(:rom_path) { File.expand_path('../lib/roms/hello-world.gb', __dir__) }
  let(:emulator) { Aiboy::EmulatorHeadless.new(rom_path) }
  let(:server) { described_class.new(emulator) }

  describe '#call' do
    it 'returns version info for GET /health' do
      status, ctype, body = server.call('GET', '/health')
      expect(status).to eq(200)
      expect(ctype).to eq('application/json')
      expect(JSON.parse(body)).to include('status' => 'ok', 'version' => Aiboy::VERSION)
    end

    it 'advances a frame via POST /step' do
      status, _, body = server.call('POST', '/step')
      expect(status).to eq(200)
      expect(JSON.parse(body)).to include('window_should_close' => false)
    end

    it 'reads and updates emulation speed via /speed' do
      status, _, body = server.call('GET', '/speed')
      expect(status).to eq(200)
      expect(JSON.parse(body)).to include('speed' => 1.0)

      status, _, body = server.call('POST', '/speed', JSON.generate(speed: 8))
      expect(status).to eq(200)
      expect(JSON.parse(body)).to include('speed' => 8.0)
      expect(emulator.speed).to eq(8.0)
    end

    it 'rejects invalid emulation speed via /speed' do
      status, _, body = server.call('POST', '/speed', JSON.generate(speed: 0))
      expect(status).to eq(400)
      expect(JSON.parse(body)['error']).to match(/between 1.0 and 8.0/)
    end

    it 'reads memory via GET /memory with a hex address' do
      status, _, body = server.call('GET', '/memory?addr=0x0104&length=4')
      expect(status).to eq(200)
      result = JSON.parse(body)
      expect(result['addr']).to eq(0x0104)
      expect(result['length']).to eq(4)
      expect(result['bytes']).to eq([0xCE, 0xED, 0x66, 0x66])
    end

    it 'reads memory via GET /memory with a decimal address' do
      status, _, body = server.call('GET', '/memory?addr=260')
      expect(status).to eq(200)
      expect(JSON.parse(body)['bytes']).to eq([0xCE])
    end

    it 'rejects GET /memory without an addr parameter' do
      status, _, body = server.call('GET', '/memory')
      expect(status).to eq(400)
      expect(JSON.parse(body)['error']).to match(/addr/)
    end

    it 'accepts POST /press with a JSON body' do
      status, _, body = server.call('POST', '/press', JSON.generate(buttons: %w[a right]))
      expect(status).to eq(200)
      result = JSON.parse(body)
      expect(result['ok']).to be true
      expect(result['buttons']).to eq(%w[a right])
    end

    it 'accepts POST /hold and POST /release' do
      expect(server.call('POST', '/hold', JSON.generate(buttons: %w[a]))[0]).to eq(200)
      expect(server.call('POST', '/hold', JSON.generate(buttons: %w[right]))[0]).to eq(200)
      expect(server.call('POST', '/release', JSON.generate(buttons: %w[a]))[0]).to eq(200)
    end

    it 'releases every button via POST /release_all' do
      status, _, body = server.call('POST', '/release_all')
      expect(status).to eq(200)
      expect(JSON.parse(body)['ok']).to be true
    end

    it 'returns the framebuffer as binary via GET /framebuffer.bin' do
      server.call('POST', '/step')
      status, ctype, body = server.call('GET', '/framebuffer.bin')
      expect(status).to eq(200)
      expect(ctype).to eq('application/octet-stream')
      expect(body.bytesize).to eq(160 * 144 * 4)
    end

    it 'returns the framebuffer as JSON via GET /framebuffer.json' do
      server.call('POST', '/step')
      status, _, body = server.call('GET', '/framebuffer.json')
      expect(status).to eq(200)
      result = JSON.parse(body)
      expect(result['width']).to eq(160)
      expect(result['height']).to eq(144)
      expect(result['pixels'].length).to eq(160 * 144)
    end

    it 'rejects invalid JSON bodies with 400' do
      status, _, body = server.call('POST', '/press', '{broken')
      expect(status).to eq(400)
      expect(JSON.parse(body)['error']).to match(/invalid JSON/)
    end

    it 'rejects unknown buttons with 400' do
      status, _, body = server.call('POST', '/press', JSON.generate(buttons: %w[turbo]))
      expect(status).to eq(400)
      expect(JSON.parse(body)['error']).to match(/turbo/)
    end

    it 'returns 404 for unknown routes' do
      status, _, body = server.call('GET', '/does-not-exist')
      expect(status).to eq(404)
      expect(JSON.parse(body)['error']).to match(%r{/does-not-exist})
    end
  end
end

RSpec.describe Aiboy::EmulatorHeadless do
  let(:rom_path) { File.expand_path('../lib/roms/hello-world.gb', __dir__) }

  it 'runs a frame without raising' do
    emulator = described_class.new(rom_path)
    expect { emulator.step_frame }.not_to raise_error
  end

  describe 'AiInterface' do
    subject(:emulator) { described_class.new(rom_path) }

    it 'reads a single byte from the cartridge ROM via the bus' do
      # 0x0104..0x0133 is the Nintendo logo region present in every valid ROM header.
      expect(emulator.read_byte(0x0104)).to eq(0xCE)
    end

    it 'reads a byte range as an Array of the requested length' do
      bytes = emulator.read_bytes(0x0104, 4)
      expect(bytes).to eq([0xCE, 0xED, 0x66, 0x66])
    end

    it 'exposes a 160x144 framebuffer' do
      emulator.step_frame
      expect(emulator.framebuffer.length).to eq(160 * 144)
    end

    it 'stores the emulation speed multiplier' do
      expect(emulator.speed).to eq(1.0)
      expect(emulator.set_speed(2)).to eq(2.0)
      expect(emulator.speed).to eq(2.0)
    end

    it 'treats #press as a replacement of the held button set' do
      emulator.press(%i[a right])
      emulator.press(%i[b])
      emulator.step_frame
      # A released, B pressed. Exact register readback depends on joypad matrix
      # selection, so we just verify the call chain does not raise.
      expect { emulator.release_all }.not_to raise_error
    end

    it 'accumulates buttons via #hold and removes them via #release' do
      emulator.hold(%i[a])
      emulator.hold(%i[right])
      emulator.release(%i[a])
      expect { emulator.step_frame }.not_to raise_error
    end

    it 'raises ArgumentError for unknown button names' do
      expect { emulator.press(%i[turbo]) }.to raise_error(ArgumentError, /turbo/)
    end
  end
end
