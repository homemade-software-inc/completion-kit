require "rails_helper"

# The docs body is a standalone partial so a host app can render it from its own
# controller — public/crawlable with YOUR_TOKEN placeholders, or in-app with a
# real token — without going through the engine's controller or its auth.
RSpec.describe "completion_kit/api_reference/_body partial", type: :request do
  def render_body(**locals)
    CompletionKit::ApplicationController.render(partial: "completion_kit/api_reference/body", locals: locals)
  end

  it "renders with just base_url, defaulting token, real_token and published_prompts" do
    html = render_body(base_url: "https://docs.example.test")

    expect(html).to include("YOUR_TOKEN")
    expect(html).not_to include("Your prompts")
    expect(html).to include("ck-api-endpoint")
    expect(html).to include("ck-mcp-tool__name")
    expect(html).to include("https://docs.example.test/api/v1/prompts")
  end

  it "shows the prompts section when published prompts are passed" do
    prompt = create(:completion_kit_prompt, name: "Crawlable Prompt")

    html = render_body(base_url: "https://app.example.test", published_prompts: [prompt])

    expect(html).to include("Your prompts")
    expect(html).to include("Crawlable Prompt")
    expect(html).to include("https://app.example.test/api/v1/prompts/#{prompt.slug}")
  end

  it "wires the real token into the copy-to-clipboard examples" do
    html = render_body(base_url: "https://app.example.test", token: "DISPLAY_TOKEN", real_token: "live-secret-9999")

    expect(html).to include('data-display-token="DISPLAY_TOKEN"')
    expect(html).to include('data-real-token="live-secret-9999"')
    expect(html).to include("Bearer DISPLAY_TOKEN")
  end
end
