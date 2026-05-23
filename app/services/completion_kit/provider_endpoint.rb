require "ipaddr"
require "resolv"

module CompletionKit
  module ProviderEndpoint
    ZERO_NET = IPAddr.new("0.0.0.0/8").freeze

    module_function

    def validate(url)
      uri = parse(url)
      return [:invalid_url] unless uri
      addrs = addresses(uri.host)
      return [:unresolvable] if addrs.empty?
      return [:unsafe_host] if addrs.any? { |ip| unsafe?(ip) }
      []
    end

    def safe?(url)
      errors = validate(url)
      errors.empty? || errors == [:unresolvable]
    end

    def parse(value)
      uri = URI.parse(value.to_s.strip)
      uri if uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      nil
    end

    def addresses(host)
      bare = host.delete_prefix("[").delete_suffix("]")
      [IPAddr.new(bare)]
    rescue IPAddr::InvalidAddressError
      Resolv.getaddresses(host).map { |addr| IPAddr.new(addr) }
    end

    def unsafe?(ip)
      return true if ip.private?
      return true if ip.link_local?
      return true if ip.to_i.zero?
      return true if ip.ipv4? && ZERO_NET.include?(ip)
      return true if ip.loopback? && !CompletionKit.config.allow_loopback_endpoints
      false
    end
  end
end
