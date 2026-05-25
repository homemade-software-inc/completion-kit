require "rails_helper"

# The docs body is a standalone partial so a host app can render it from its own
# controller — public/crawlable with YOUR_TOKEN placeholders, or in-app with a
# real token — without going through the engine's controller or its auth.
RSpec.describe "completion_kit/api_reference/_body partial", type: :request do
  def render_body(**locals)
    CompletionKit::ApplicationController.render(partial: "completion_kit/api_reference/body", locals: locals)
  end

  it "renders with just base_url, defaulting every collection to empty" do
    html = render_body(base_url: "https://docs.example.test")

    expect(html).to include("YOUR_TOKEN")
    %w[
      Your\ published\ prompts
      Your\ recent\ runs
      Your\ responses
      Your\ datasets
      Your\ metrics
      Your\ metric\ groups
      Your\ tags
      Your\ providers
    ].each { |heading| expect(html).not_to include(heading) }
    expect(html).not_to include("ck-api-prompts-section")
    expect(html).to include("ck-api-endpoint")
    expect(html).to include("ck-mcp-tool__name")
    expect(html).to include("https://docs.example.test/api/v1/prompts")
  end

  it "lists the published prompts inside the Prompts section" do
    prompt = create(:completion_kit_prompt, name: "Crawlable Prompt")

    html = render_body(base_url: "https://app.example.test", published_prompts: [prompt])

    expect(html).to include("Your published prompts")
    expect(html).not_to include("ck-api-prompts-section")
    expect(html).to include("Crawlable Prompt")
    expect(html).to include("https://app.example.test/api/v1/prompts/#{prompt.slug}")
  end

  it "wires the real token into the copy-to-clipboard examples" do
    html = render_body(base_url: "https://app.example.test", token: "DISPLAY_TOKEN", real_token: "live-secret-9999")

    expect(html).to include('data-display-token="DISPLAY_TOKEN"')
    expect(html).to include('data-real-token="live-secret-9999"')
    expect(html).to include("Bearer DISPLAY_TOKEN")
  end

  it "fills every section with the real records when their collections are passed" do
    prompt = create(:completion_kit_prompt, name: "Live Prompt")
    run = create(:completion_kit_run, prompt: prompt, name: "Nightly Run", status: "completed")
    dataset = create(:completion_kit_dataset, name: "Tickets", csv_data: "text,expected\nhello,hi\nbye,goodbye\n")
    metric = create(:completion_kit_metric, name: "Accuracy", instruction: "Is the response factually correct?")
    metric_group = create(:completion_kit_metric_group, name: "Reply Quality")
    metric_group.metrics << metric
    tag = create(:completion_kit_tag, name: "marine biology", color: "electric-cyan")
    provider = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")

    base = "https://app.example.test"
    html = render_body(
      base_url: base,
      published_prompts: [prompt],
      recent_runs: [run],
      datasets: [dataset],
      metrics: [metric],
      metric_groups: [metric_group],
      tags: [tag],
      provider_credentials: [provider]
    )

    expect(html).to include("Your published prompts")
    expect(html).to include("Live Prompt")
    expect(html).to include("#{base}/api/v1/prompts/#{prompt.slug}")

    expect(html).to include("Your recent runs")
    expect(html).to include("Nightly Run")
    expect(html).to include("Completed")
    expect(html).to include("#{base}/api/v1/runs/#{run.id}")

    expect(html).to include("Your responses")
    expect(html).to include("Nightly Run — responses")
    expect(html).to include("#{base}/api/v1/runs/#{run.id}/responses")

    expect(html).to include("Your datasets")
    expect(html).to include("Tickets")
    expect(html).to include("2 entries")
    expect(html).to include("#{base}/api/v1/datasets/#{dataset.id}")

    expect(html).to include("Your metrics")
    expect(html).to include("Accuracy")
    expect(html).to include("Is the response factually correct?")
    expect(html).to include("#{base}/api/v1/metrics/#{metric.id}")

    expect(html).to include("Your metric groups")
    expect(html).to include("Reply Quality")
    expect(html).to include("1 metric")
    expect(html).to include("#{base}/api/v1/metric_groups/#{metric_group.id}")

    expect(html).to include("Your tags")
    expect(html).to include("marine biology")
    expect(html).to include("electric-cyan")
    expect(html).to include("#{base}/api/v1/tags/#{tag.id}")

    expect(html).to include("Your providers")
    expect(html).to include("OpenAI")
    expect(html).to include("#{base}/api/v1/provider_credentials/#{provider.id}")
  end
end
