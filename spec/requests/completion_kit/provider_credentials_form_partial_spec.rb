require "rails_helper"

RSpec.describe "CompletionKit provider credential form partial", type: :request do
  def render_form(**locals)
    CompletionKit::ProviderCredentialsController.render(
      partial: "completion_kit/provider_credentials/form",
      locals: { provider_credential: CompletionKit::ProviderCredential.new }.merge(locals)
    )
  end

  it "posts to the supplied url and hides Cancel when cancel_path is false" do
    html = render_form(url: "/x/key", cancel_path: false)

    expect(html).to include('action="/x/key"')
    expect(html).not_to include("Cancel")
  end

  it "uses the supplied cancel_path for the Cancel link" do
    html = render_form(cancel_path: "/back")

    expect(html).to include('href="/back"')
  end

  it "renders the engine defaults without the locals" do
    html = render_form

    expect(html).to include('action="/completion_kit/provider_credentials"')
    expect(html).to include('href="/completion_kit/provider_credentials"')
    expect(html).to include("Cancel")
  end
end
