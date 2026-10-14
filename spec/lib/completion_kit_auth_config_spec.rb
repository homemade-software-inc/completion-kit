require "rails_helper"

RSpec.describe "CompletionKit auth configuration" do
  after { CompletionKit.instance_variable_set(:@config, nil) }

  it "exposes username, password, and auth_strategy" do
    CompletionKit.configure do |c|
      c.username = "admin"
      c.password = "secret"
    end

    expect(CompletionKit.config.username).to eq("admin")
    expect(CompletionKit.config.password).to eq("secret")
    expect(CompletionKit.config.auth_strategy).to be_nil
  end

  it "exposes auth_strategy" do
    strategy = ->(controller) { controller.head(:unauthorized) }

    CompletionKit.configure do |c|
      c.auth_strategy = strategy
    end

    expect(CompletionKit.config.auth_strategy).to eq(strategy)
  end

  it "defaults current_reviewer to nil" do
    expect(CompletionKit.config.current_reviewer).to be_nil
  end

  it "exposes current_reviewer" do
    reviewer = ->(controller) { controller.request.headers["X-Remote-User"] }

    CompletionKit.configure do |c|
      c.current_reviewer = reviewer
    end

    expect(CompletionKit.config.current_reviewer).to eq(reviewer)
  end

  it "exposes api_token" do
    CompletionKit.configure do |c|
      c.api_token = "test-token-123"
    end
    expect(CompletionKit.config.api_token).to eq("test-token-123")
  end

  it "defaults api_token to nil" do
    expect(CompletionKit.config.api_token).to be_nil
  end
end
