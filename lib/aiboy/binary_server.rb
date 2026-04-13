# frozen_string_literal: true

require 'socket'
require_relative 'version'

module Aiboy
  # Fast binary protocol for driving the emulator from external programs.
  #
  # HttpServer is great for debugging but HTTP/JSON parsing dominates the
  # per-call cost on localhost. BinaryServer strips the wire format down
  # to length-prefixed binary frames so an agent in any language can step
  # the emulator tens of thousands of times per second.
  #
  # === Wire format
  #
  # All integers are little-endian. Every request and every response is a
  # length-prefixed frame:
  #
  #     frame = u32le(length) ++ bytes(length)
  #
  # A request frame's payload is (opcode:u8 ++ opcode_args). A response
  # frame's payload is (status:u8 ++ status_body). status is 0x00 for
  # success or 0xFF for error; on error the body is a UTF-8 error message.
  #
  # === Opcodes
  #
  #     0x01 PING              → "PONG" (4 bytes)
  #     0x02 VERSION           → VERSION string (UTF-8, variable length)
  #     0x03 STEP              → window_should_close:u8 (0 or 1)
  #     0x04 READ_BYTE         args: addr:u16           → value:u8
  #     0x05 READ_BYTES        args: addr:u16, len:u16  → len bytes
  #     0x06 PRESS             args: mask:u8            → empty
  #     0x07 HOLD              args: mask:u8            → empty
  #     0x08 RELEASE           args: mask:u8            → empty
  #     0x09 RELEASE_ALL                                → empty
  #     0x0A FRAMEBUFFER                                → 92_160 bytes raw ABGR8888
  #     0x0B QUIT                                       → empty (server closes the connection)
  #
  # Button bitmask (u8), one bit per button:
  #
  #     bit 0: right     bit 4: a
  #     bit 1: left      bit 5: b
  #     bit 2: up        bit 6: select
  #     bit 3: down      bit 7: start
  #
  # A persistent connection handles many requests in sequence — no
  # reconnect overhead between frames.
  class BinaryServer
    DEFAULT_PORT = 9877
    DEFAULT_HOST = '127.0.0.1'

    STATUS_OK = 0x00
    STATUS_ERROR = 0xFF

    OP_PING         = 0x01
    OP_VERSION      = 0x02
    OP_STEP         = 0x03
    OP_READ_BYTE    = 0x04
    OP_READ_BYTES   = 0x05
    OP_PRESS        = 0x06
    OP_HOLD         = 0x07
    OP_RELEASE      = 0x08
    OP_RELEASE_ALL  = 0x09
    OP_FRAMEBUFFER  = 0x0A
    OP_QUIT         = 0x0B

    BUTTON_ORDER = %i[right left up down a b select start].freeze

    def initialize(emulator, host: DEFAULT_HOST, port: DEFAULT_PORT, logger: $stderr)
      @emulator = emulator
      @host = host
      @port = port
      @logger = logger
    end

    def start
      server = TCPServer.new(@host, @port)
      @logger&.puts "Aiboy::BinaryServer listening on tcp://#{@host}:#{server.addr[1]}"
      loop do
        client = nil
        begin
          client = server.accept
          serve_client(client)
        rescue Interrupt
          break
        ensure
          client&.close
        end
      end
    ensure
      server&.close
    end

    # Dispatch a single request payload and return the response payload.
    # Exposed separately from the socket loop so specs can exercise the
    # protocol without opening a real TCP port.
    def dispatch(payload)
      return pack_error('empty request payload') if payload.nil? || payload.empty?

      opcode = payload.getbyte(0)
      args = payload.byteslice(1, payload.bytesize - 1) || ''.b
      handler = HANDLERS[opcode]
      return pack_error("unknown opcode 0x#{opcode.to_s(16).rjust(2, '0')}") unless handler

      result = send(handler, args)
      "\x00".b + result.to_s.b
    rescue ArgumentError, RangeError => e
      pack_error(e.message)
    rescue StandardError => e
      pack_error("#{e.class}: #{e.message}")
    end

    HANDLERS = {
      OP_PING => :handle_ping,
      OP_VERSION => :handle_version,
      OP_STEP => :handle_step,
      OP_READ_BYTE => :handle_read_byte,
      OP_READ_BYTES => :handle_read_bytes,
      OP_PRESS => :handle_press,
      OP_HOLD => :handle_hold,
      OP_RELEASE => :handle_release,
      OP_RELEASE_ALL => :handle_release_all,
      OP_FRAMEBUFFER => :handle_framebuffer,
      OP_QUIT => :handle_quit
    }.freeze
    private_constant :HANDLERS

    private

    def serve_client(client)
      # Disable Nagle so small request/response frames don't get stuck in
      # the 40ms delayed-ACK x Nagle interaction. Without this a simple
      # PING → PONG round-trip pins at ~25 ops/sec on Linux localhost
      # because the 1-byte reply is below Nagle's send threshold and the
      # kernel waits up to 40ms for more data before flushing. With
      # TCP_NODELAY, the same path runs at 30k+ ops/sec — which is what
      # you want for a high-frequency agent.
      client.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      length_buf = String.new(capacity: 4)
      loop do
        read_exact(client, 4, length_buf) or return
        length = length_buf.unpack1('V')
        return if length == 0
        raise "frame too large: #{length}" if length > 10_485_760 # 10 MiB guard

        payload = String.new(capacity: length)
        read_exact(client, length, payload) or return

        response = dispatch(payload)
        client.write([response.bytesize].pack('V'))
        client.write(response)

        break if payload.getbyte(0) == OP_QUIT
      end
    end

    def read_exact(client, n, buffer)
      buffer.clear
      while buffer.bytesize < n
        chunk = client.read(n - buffer.bytesize)
        return false if chunk.nil?

        buffer << chunk
      end
      true
    end

    def pack_error(message)
      message = message.to_s.b
      raise 'error message too long' if message.bytesize > 65_535

      "\xFF".b + message
    end

    def handle_ping(_args)
      'PONG'.b
    end

    def handle_version(_args)
      Aiboy::VERSION.b
    end

    def handle_step(_args)
      should_close = @emulator.step_frame ? 1 : 0
      [should_close].pack('C')
    end

    def handle_read_byte(args)
      raise ArgumentError, 'READ_BYTE needs addr:u16' if args.bytesize < 2

      addr = args.unpack1('v')
      [@emulator.read_byte(addr)].pack('C')
    end

    def handle_read_bytes(args)
      raise ArgumentError, 'READ_BYTES needs addr:u16, len:u16' if args.bytesize < 4

      addr, length = args.unpack('vv')
      raise ArgumentError, 'length must be >= 1' if length == 0

      @emulator.read_bytes(addr, length).pack('C*')
    end

    def handle_press(args)
      buttons = decode_button_mask(args)
      @emulator.press(buttons)
      ''.b
    end

    def handle_hold(args)
      buttons = decode_button_mask(args)
      @emulator.hold(buttons)
      ''.b
    end

    def handle_release(args)
      buttons = decode_button_mask(args)
      @emulator.release(buttons)
      ''.b
    end

    def handle_release_all(_args)
      @emulator.release_all
      ''.b
    end

    def handle_framebuffer(_args)
      @emulator.framebuffer.pack('V*')
    end

    def handle_quit(_args)
      ''.b
    end

    def decode_button_mask(args)
      raise ArgumentError, 'mask byte missing' if args.empty?

      mask = args.getbyte(0)
      BUTTON_ORDER.each_with_index.filter_map { |name, bit| name if mask[bit] == 1 }
    end
  end
end
