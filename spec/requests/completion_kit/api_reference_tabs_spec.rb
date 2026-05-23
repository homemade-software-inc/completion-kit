require "rails_helper"

# The API reference tab strip is a CSS-only widget: one radio per tab, one panel
# per tab (in the same order), and a hand-written stylesheet rule per tab that
# shows panel :nth-child(N) when radio N is checked. That mapping has silently
# drifted before — a tab was added/renamed in the ERB but the CSS still listed
# the old set, so some panels rendered blank. This guards the invariant.
RSpec.describe "CompletionKit API reference tabs", type: :request do
  let(:css) do
    File.read(CompletionKit::Engine.root.join("app/assets/stylesheets/completion_kit/application.css.erb"))
  end

  it "keeps the tab radios, panels, and the tab CSS in sync" do
    get "/completion_kit/api_reference"
    body = response.body

    tab_ids = body.scan(/<input[^>]*name="ck-api-tab"[^>]*id="(ck-tab-[\w-]+)"/).flatten
    panel_count = body.scan(/<div class="ck-api-tabs__panel">/).count

    expect(tab_ids).not_to be_empty
    expect(panel_count).to eq(tab_ids.size)

    rule_for = css
      .scan(/#(ck-tab-[\w-]+):checked ~ \.ck-api-tabs__panels \.ck-api-tabs__panel:nth-child\((\d+)\)/)
      .to_h { |id, n| [id, n.to_i] }

    expect(rule_for.size).to eq(tab_ids.size)

    tab_ids.each_with_index do |id, index|
      expect(rule_for[id]).to eq(index + 1),
        "expected the CSS to reveal panel #{index + 1} when ##{id} is checked, but found #{rule_for[id].inspect}"
    end

    expect(rule_for.keys - tab_ids).to be_empty, "stale tab id(s) in the CSS: #{(rule_for.keys - tab_ids).inspect}"
  end
end
