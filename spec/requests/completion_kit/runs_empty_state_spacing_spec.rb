require "rails_helper"

RSpec.describe "CompletionKit empty runs box spacing", type: :request do
  let(:css) { File.read(CompletionKit::Engine.root.join("app/assets/stylesheets/completion_kit/application.css")) }
  let(:table_gap) do
    File.read(CompletionKit::Engine.root.join("app/views/completion_kit/runs/_table.html.erb"))[/ck-runs-table" style="margin-top: ([^;]+);/, 1]
  end

  before { CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) } }
  after { CompletionKit.config.runs_display_scope = nil }

  def gap_after(heading_class)
    rule = css.scan(/([^{}]+)\{([^}]*)\}/).find do |selectors, _|
      selectors.split(",").map(&:strip).include?(".#{heading_class} + .ck-empty")
    end
    rule && rule.last[/margin-top:\s*([^;]+);/, 1]
  end

  def heading_before_empty_box
    box = Nokogiri::HTML5(response.body).css("div.ck-empty").find { |node| node.text.strip == "No runs to show." }
    box.previous_element["class"]
  end

  it "sits as far below the Runs heading as the table does on the prompt page" do
    prompt = create(:completion_kit_prompt)
    create(:completion_kit_run, prompt: prompt, created_at: 90.days.ago)

    get "/completion_kit/prompts/#{prompt.id}"

    expect(heading_before_empty_box).to eq("ck-kicker")
    expect(gap_after("ck-kicker")).to eq(table_gap)
  end

  it "sits as far below the Runs heading as the table does on the dataset page" do
    dataset = create(:completion_kit_dataset)
    create(:completion_kit_run, dataset: dataset, created_at: 90.days.ago)

    get "/completion_kit/datasets/#{dataset.id}"

    expect(heading_before_empty_box).to eq("ck-kicker")
    expect(gap_after("ck-kicker")).to eq(table_gap)
  end

  it "sits as far below the Recent runs heading as the table does on the dashboard" do
    cookies[:ck_onboarding_dismissed] = "1"
    create(:completion_kit_run, created_at: 90.days.ago)

    get "/completion_kit/dashboard"

    expect(heading_before_empty_box).to eq("ck-split")
    expect(gap_after("ck-split")).to eq(table_gap)
  end
end
