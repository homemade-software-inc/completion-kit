require "ipaddr"
require "socket"

module CompletionKit
  module ProviderEndpoint
    class UnsafeEndpoint < StandardError; end

    BLOCKED_NETS = [IPAddr.new("0.0.0.0/8"), IPAddr.new("100.64.0.0/10")].freeze
    ISSUE_MESSAGES = {
      invalid_url: "is not a valid http or https URL",
      unresolvable: "could not be resolved",
      unsafe_host: "resolves to a private address"
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
      return true if ip.private?
      return true if ip.link_local?
      return true if ip.to_i.zero?
      return true if ip.ipv4? && BLOCKED_NETS.any? { |net| net.include?(ip) }
      return true if ip.loopback? && !CompletionKit.config.allow_loopback_endpoints
      false
    end
  end
end
