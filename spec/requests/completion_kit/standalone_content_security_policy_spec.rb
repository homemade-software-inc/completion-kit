require "rails_helper"

RSpec.describe "The standalone app's nonce-based script policy", type: :request do
  before(:context) do
    @standalone_config = Rails::Application::Configuration.new(Rails.root)
    application = Struct.new(:config) { def configure(&) = instance_eval(&) }.new(@standalone_config)
    RSpec::Mocks.with_temporary_scope do
      allow(Rails).to receive(:application).and_return(application)
      load File.expand_path("../../../standalone/config/initializers/content_security_policy.rb", __dir__)
    end
  end

  let(:browser_accept) { "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" }
  let(:token) { "standalone-csp-token-0123456789" }

  before do
    config = @standalone_config
    allow(Rails.application).to receive(:env_config).and_wrap_original do |original|
      original.call.merge(
        "action_dispatch.content_security_policy" => config.content_security_policy,
        "action_dispatch.content_security_policy_nonce_generator" => config.content_security_policy_nonce_generator,
        "action_dispatch.content_security_policy_nonce_directives" => config.content_security_policy_nonce_directives
      )
    end
    CompletionKit.config.api_token = token
  end

  after { CompletionKit.config.api_token = nil }

  def nonce_in(header)
    header.to_s[/'nonce-([^']+)'/, 1]
  end

  it "gives a brand-new visitor's first HTML page a nonce that the page and its header share" do
    get "/completion_kit/prompts", headers: {"Accept" => browser_accept}

    expect(response).to have_http_status(:ok)
    nonce = nonce_in(response.headers["Content-Security-Policy"])
    expect(nonce).to be_present
    document = Nokogiri::HTML5(response.body)
    expect(document.at_css('meta[name="csp-nonce"]')["content"]).to eq(nonce)
    expect(document.css("script").map { |script| script["nonce"] }.uniq).to eq([nonce])
  end

  it "keeps the same nonce across a visitor's Turbo Drive visits" do
    get "/completion_kit/prompts", headers: {"Accept" => browser_accept}
    first = nonce_in(response.headers["Content-Security-Policy"])

    get "/completion_kit/metrics", headers: {"Accept" => "text/html, application/xhtml+xml"}

    expect(nonce_in(response.headers["Content-Security-Policy"])).to eq(first)
  end

  it "answers a JSON API call without a session cookie or a nonce source" do
    get "/completion_kit/api/v1/prompts", headers: {"Authorization" => "Bearer #{token}", "Accept" => "application/json"}

    expect(response).to have_http_status(:ok)
    expect(response.headers["Set-Cookie"]).to be_nil
    expect(response.headers["Content-Security-Policy"]).to include("script-src 'self'")
    expect(response.headers["Content-Security-Policy"]).not_to include("nonce-")
  end

  it "answers an API call that accepts anything without a session cookie" do
    get "/completion_kit/api/v1/prompts", headers: {"Authorization" => "Bearer #{token}", "Accept" => "*/*"}

    expect(response).to have_http_status(:ok)
    expect(response.headers["Set-Cookie"]).to be_nil
  end

  it "answers an MCP call without a session cookie or a nonce source" do
    post "/completion_kit/mcp", params: {jsonrpc: "2.0", method: "initialize", id: 1}.to_json,
      headers: {"Content-Type" => "application/json", "Accept" => "application/json, text/event-stream"}

    expect(response).to have_http_status(:ok)
    expect(response.headers["Set-Cookie"]).to be_nil
    expect(response.headers["Content-Security-Policy"]).not_to include("nonce-")
  end
end
