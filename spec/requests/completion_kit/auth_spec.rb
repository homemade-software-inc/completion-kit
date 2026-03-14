require "rails_helper"

RSpec.describe "CompletionKit authentication", type: :request do
  let(:base_path) { "/completion_kit/prompts" }

  after { CompletionKit.instance_variable_set(:@config, nil) }

  context "with basic auth configured" do
    before do
      CompletionKit.configure do |c|
        c.username = "admin"
        c.password = "secret"
      end
    end

    it "allows access with correct credentials" do
      create(:completion_kit_prompt)

      get base_path, headers: {
        "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "secret")
      }

      expect(response).to have_http_status(:ok)
    end

    it "rejects access with wrong credentials" do
      get base_path, headers: {
        "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "wrong")
      }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects access with no credentials" do
      get base_path

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with custom auth_strategy" do
    before do
      CompletionKit.configure do |c|
        c.auth_strategy = ->(controller) {
          controller.head(:unauthorized) unless controller.request.headers["X-Custom-Auth"] == "valid"
        }
      end
    end

    it "allows access when strategy passes" do
      create(:completion_kit_prompt)

      get base_path, headers: { "X-Custom-Auth" => "valid" }

      expect(response).to have_http_status(:ok)
    end

    it "rejects access when strategy fails" do
      get base_path, headers: { "X-Custom-Auth" => "invalid" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with both basic auth and auth_strategy configured" do
    before do
      CompletionKit.configure do |c|
        c.username = "admin"
        c.password = "secret"
        c.auth_strategy = ->(controller) { true }
      end
    end

    it "raises ConfigurationError" do
      expect { get base_path }.to raise_error(
        CompletionKit::ConfigurationError,
        /Cannot configure both/
      )
    end
  end

  context "with only username set (no password)" do
    before do
      CompletionKit.configure do |c|
        c.username = "admin"
      end
    end

    it "raises ConfigurationError" do
      expect { get base_path }.to raise_error(
        CompletionKit::ConfigurationError,
        /Both username and password are required/
      )
    end
  end

  context "with no auth in non-production" do
    it "allows open access" do
      create(:completion_kit_prompt)

      get base_path

      expect(response).to have_http_status(:ok)
    end
  end

  context "with no auth in production" do
    around do |example|
      original_env = Rails.env
      Rails.env = ActiveSupport::EnvironmentInquirer.new("production")
      example.run
    ensure
      Rails.env = original_env
    end

    it "blocks access with 403" do
      get base_path

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("authentication not configured")
    end
  end
end
