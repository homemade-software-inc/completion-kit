require "faraday"

module TransportErrors
  LEAKED_TEXT = [
    "Connection refused",
    "execution expired",
    "ReadTimeout",
    "wrong status line",
    "unexpected character",
    "SSH-2.0",
    "peeraddr",
    "10.9.8.7"
  ].freeze

  def self.samples
    {
      "a refused port" => Faraday::ConnectionFailed.new(%(Failed to open TCP connection to 10.9.8.7:22 (Connection refused - connect(2) for "10.9.8.7" port 22))),
      "a connect timeout" => Faraday::TimeoutError.new("Failed to open TCP connection to 10.9.8.7:81 (execution expired)"),
      "a read timeout" => Faraday::TimeoutError.new("Net::ReadTimeout with #<TCPSocket:(closed)>"),
      "a service that is not HTTP" => Faraday::ConnectionFailed.new(%(wrong status line: "SSH-2.0-OpenSSH_9.6 test")),
      "a TLS failure" => Faraday::SSLError.new("SSL_connect returned=1 errno=0 peeraddr=10.9.8.7:443 state=error: certificate verify failed")
    }
  end

  def self.not_json
    JSON::ParserError.new("unexpected character: '<html><title>Internal' at line 1 column 1")
  end

  def self.leaks?(text)
    LEAKED_TEXT.any? { |fragment| text.to_s.include?(fragment) }
  end
end
