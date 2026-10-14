require "ipaddr"
require "socket"

module CompletionKit
  module ProviderEndpoint
    class UnsafeEndpoint < StandardError; end

    BLOCKED_NETS = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24
      192.88.99.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      2001::/23 2001:db8::/32 2002::/16 3fff::/20
    ].map { |net| IPAddr.new(net) }.freeze
    GLOBAL_UNICAST = IPAddr.new("2000::/3")
    NAT64 = IPAddr.new("64:ff9b::/96")
    ISSUE_MESSAGES = {
      invalid_url: "is not a valid http or https URL",
      unresolvable: "does not resolve to a public address",
      unsafe_host: "does not resolve to a public address"
    }.freeze

    module_function

    def validate(url)
      uri = parse(url)
      return [:invalid_url] unless uri
      issues_for(addresses(uri.host))
    end

    def safe?(url)
      validate(url).empty?
    end

    def pinned_address(url)
      uri = parse(url)
      raise UnsafeEndpoint, ISSUE_MESSAGES[:invalid_url] unless uri
      addrs = addresses(uri.host)
      issue = issues_for(addrs).first
      raise UnsafeEndpoint, ISSUE_MESSAGES[issue] if issue
      (addrs.find(&:ipv4?) || addrs.first).to_s
    end

    def pin(builder, url)
      address = pinned_address(url)
      builder.adapter(:net_http) { |http| http.ipaddr = address }
    end

    def parse(value)
      uri = URI.parse(value.to_s.strip)
      uri if uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      nil
    end

    def issues_for(addrs)
      return [:unresolvable] if addrs.empty?
      return [:unsafe_host] if addrs.any? { |ip| unsafe?(ip) }
      []
    end

    def addresses(host)
      bare = host.delete_prefix("[").delete_suffix("]").delete_suffix(".")
      [IPAddr.new(bare)]
    rescue IPAddr::InvalidAddressError
      resolve(bare).map { |addr| IPAddr.new(addr) }
    end

    def resolve(host)
      Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
    rescue SocketError
      []
    end

    def unsafe?(ip)
      ip = ip.native
      return !CompletionKit.config.allow_loopback_endpoints if ip.loopback?
      return nat64_unsafe?(ip) if NAT64.include?(ip)
      return true if ip.ipv6? && !GLOBAL_UNICAST.include?(ip)
      BLOCKED_NETS.any? { |net| net.include?(ip) }
    end

    def nat64_unsafe?(ip)
      target = IPAddr.new(ip.to_i & 0xffff_ffff, Socket::AF_INET)
      target.loopback? || unsafe?(target)
    end
  end
end
