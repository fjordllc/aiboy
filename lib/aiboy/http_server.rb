# frozen_string_literal: true

require 'socket'
require 'json'
require_relative 'version'

module Aiboy
  # Human-friendly HTTP/JSON interface over AiInterface.
  #
  # This is the debug/convenience path — useful with curl, browsers, and
  # ad-hoc scripts. For performance-sensitive agents use Aiboy::BinaryServer
  # instead, which avoids HTTP/JSON overhead entirely.
  class HttpServer
    DEFAULT_PORT = 9876
    DEFAULT_HOST = '127.0.0.1'

    STATUS_TEXTS = {
      200 => 'OK',
      204 => 'No Content',
      400 => 'Bad Request',
      404 => 'Not Found',
      405 => 'Method Not Allowed',
      500 => 'Internal Server Error'
    }.freeze

    def initialize(emulator, host: DEFAULT_HOST, port: DEFAULT_PORT, logger: $stderr)
      @emulator = emulator
      @host = host
      @port = port
      @logger = logger
    end

    # Run the accept loop until interrupted. Blocks the current thread.
    def start
      server = TCPServer.new(@host, @port)
      actual_port = server.addr[1]
      @logger&.puts "Aiboy::HttpServer listening on http://#{@host}:#{actual_port}"
      loop do
        client = nil
        begin
          client = server.accept
          handle_connection(client)
        rescue Interrupt
          break
        ensure
          client&.close
        end
      end
    ensure
      server&.close
    end

    # Dispatch a single request. Exposed separately from the socket loop so
    # specs can exercise every endpoint without opening a real TCP port.
    # Returns [status_code, content_type, body].
    def call(method, path, body = nil)
      base, query = path.split('?', 2)
      route = "#{method} #{base}"
      case route
      when 'GET /health'
        json_ok(status: 'ok', version: Aiboy::VERSION)
      when 'POST /step'
        should_close = @emulator.step_frame ? true : false
        json_ok(window_should_close: should_close)
      when 'GET /speed'
        json_ok(speed: @emulator.speed)
      when 'POST /speed'
        handle_speed(body)
      when 'GET /memory'
        handle_memory(query)
      when 'POST /press'
        handle_buttons(body) { |buttons| @emulator.press(buttons) }
      when 'POST /hold'
        handle_buttons(body) { |buttons| @emulator.hold(buttons) }
      when 'POST /release'
        handle_buttons(body) { |buttons| @emulator.release(buttons) }
      when 'POST /release_all'
        @emulator.release_all
        json_ok(ok: true)
      when 'GET /framebuffer.json'
        json_ok(width: 160, height: 144, pixels: @emulator.framebuffer)
      when 'GET /framebuffer.bin'
        [200, 'application/octet-stream', @emulator.framebuffer.pack('V*')]
      when 'OPTIONS /'
        [204, 'text/plain', '']
      else
        json_error(404, "no route for #{route}")
      end
    rescue JSON::ParserError => e
      json_error(400, "invalid JSON body: #{e.message}")
    rescue ArgumentError => e
      json_error(400, e.message)
    rescue StandardError => e
      json_error(500, "#{e.class}: #{e.message}")
    end

    private

    def handle_connection(client)
      client.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      request = read_request(client)
      return unless request

      method, path, body = request
      status, content_type, response_body = call(method, path, body)
      write_response(client, status, content_type, response_body)
    end

    def read_request(client)
      request_line = client.gets
      return nil unless request_line

      method, path, = request_line.chomp.split
      return nil unless method && path

      headers = {}
      while (line = client.gets)
        stripped = line.chomp
        break if stripped.empty?

        key, value = stripped.split(': ', 2)
        headers[key.downcase] = value if key && value
      end

      content_length = headers['content-length'].to_i
      body = content_length > 0 ? client.read(content_length) : nil
      [method, path, body]
    end

    def write_response(client, status, content_type, body)
      body = (body || '').to_s
      client.write("HTTP/1.1 #{status} #{STATUS_TEXTS.fetch(status, 'Unknown')}\r\n")
      client.write("Content-Type: #{content_type}\r\n")
      client.write("Content-Length: #{body.bytesize}\r\n")
      client.write("Access-Control-Allow-Origin: *\r\n")
      client.write("Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n")
      client.write("Access-Control-Allow-Headers: Content-Type\r\n")
      client.write("Connection: close\r\n")
      client.write("\r\n")
      client.write(body)
    end

    def handle_speed(body)
      payload = body && !body.empty? ? JSON.parse(body) : {}
      raise ArgumentError, 'speed is required' unless payload.key?('speed')

      json_ok(speed: @emulator.set_speed(payload['speed']))
    end

    def handle_memory(query)
      params = parse_query(query)
      addr = parse_int(params['addr'])
      raise ArgumentError, 'addr query parameter is required' unless addr

      length = parse_int(params['length']) || 1
      raise ArgumentError, 'length must be >= 1' if length < 1
      raise ArgumentError, 'length must be <= 65536' if length > 65_536

      bytes = @emulator.read_bytes(addr, length)
      json_ok(addr: addr, length: length, bytes: bytes)
    end

    def handle_buttons(body)
      payload = body && !body.empty? ? JSON.parse(body) : {}
      buttons = Array(payload['buttons']).map(&:to_sym)
      yield buttons
      json_ok(ok: true, buttons: buttons.map(&:to_s))
    end

    def parse_query(query)
      return {} unless query

      query.split('&').each_with_object({}) do |pair, hash|
        key, value = pair.split('=', 2)
        hash[key] = value if key
      end
    end

    # Accepts "53092", "0xCF64", or "0XCF64".
    def parse_int(str)
      return nil if str.nil? || str.empty?

      str = str.strip
      return str.to_i(16) if str.start_with?('0x', '0X')

      Integer(str, 10)
    rescue ArgumentError
      nil
    end

    def json_ok(data)
      [200, 'application/json', JSON.generate(data)]
    end

    def json_error(status, message)
      [status, 'application/json', JSON.generate(error: message)]
    end
  end
end
