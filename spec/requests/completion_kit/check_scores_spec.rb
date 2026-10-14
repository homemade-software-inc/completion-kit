require "rails_helper"

RSpec.describe "Fractional check scores on run pages", type: :request do
  let(:prompt) { create(:completion_kit_prompt, template: "Static") }
  let(:dataset) { create(:completion_kit_dataset, csv_data: "input\nhi\n") }
  let(:metric) do
    create(:completion_kit_metric, :check, name: "Codes",
           check_config: { "check_kind" => "list_overlap", "target" => "response_text", "value" => "A, B, C, D" })
  end

  def scored_run(score, passed: false)
    run = create(:completion_kit_run, prompt: prompt, dataset: dataset, status: "completed", progress_total: 1)
    run.run_metrics.create!(metric: metric, position: 1)
    row = create(:completion_kit_response, run: run, input_data: "hi", response_text: "A, B", status: "succeeded")
    create(:completion_kit_review, :check, response: row, metric: metric, metric_name: metric.name,
           passed: passed, check_score: score)
    [run, row]
  end

  def pip_labels(html)
    Nokogiri::HTML5(html).css(".ck-metric-pip__label").map { |node| node.text.squish }
  end

  it "shows a row's fraction rather than a bare fail on the run page" do
    run, = scored_run(0.5)

    get "/completion_kit/runs/#{run.id}"

    pips = Nokogiri::HTML5(response.body).css("[role=img][aria-label='Codes score 0.5']")
    expect(pips).not_to be_empty
    expect(pip_labels(response.body)).to include("Codes 0.5")
  end

  it "shows the run's average fraction in the status panel" do
    run, = scored_run(0.5)

    get "/completion_kit/runs/#{run.id}"

    panel = Nokogiri::HTML5(response.body).at_css("#run_status_panel")
    expect(panel.css(".ck-metric-pip__label").map { |node| node.text.squish }).to include("Codes 0.5")
  end

  it "shows the average fraction in the runs list the way the status panel does" do
    scored_run(0.5)

    get "/completion_kit/runs"

    expect(Nokogiri::HTML5(response.body).css("[role=img][aria-label='Codes score 0.5']")).not_to be_empty
    expect(pip_labels(response.body)).to include("Codes 0.5")
    expect(pip_labels(response.body)).not_to include("Codes 0%")
  end

  it "keeps the pass rate in the runs list for a check with no fraction" do
    run = create(:completion_kit_run, prompt: prompt, dataset: dataset, status: "completed")
    check = create(:completion_kit_metric, :check, name: "Shape")
    row = create(:completion_kit_response, run: run, input_data: "hi", status: "succeeded")
    create(:completion_kit_review, :check, response: row, metric: check, metric_name: check.name, passed: true)

    get "/completion_kit/runs"

    expect(Nokogiri::HTML5(response.body).css("[role=img][aria-label='Shape 100% pass rate']")).not_to be_empty
  end

  it "shows a fraction that moved between runs even when the verdict did not" do
    left, = scored_run(0.5)
    right, = scored_run(0.8333)

    get "/completion_kit/runs/#{left.id}/compare", params: { with: right.id }

    page = Nokogiri::HTML5(response.body)
    expect(page.css(".ck-cmp-score .ck-badge").map(&:text)).to eq(["Fail 0.5", "Fail 0.83"])
    expect(page.at_css(".ck-cmp-delta").text.squish).to eq("▲+0.33")
  end

  it "still marks a flipped verdict on a check with no fraction" do
    left = create(:completion_kit_run, prompt: prompt, dataset: dataset, status: "completed")
    right = create(:completion_kit_run, prompt: prompt, dataset: dataset, status: "completed")
    check = create(:completion_kit_metric, :check, name: "Shape")
    create(:completion_kit_review, :check, response: create(:completion_kit_response, run: left, input_data: "hi"),
           metric: check, metric_name: check.name, passed: false)
    create(:completion_kit_review, :check, response: create(:completion_kit_response, run: right, input_data: "hi"),
           metric: check, metric_name: check.name, passed: true)

    get "/completion_kit/runs/#{left.id}/compare", params: { with: right.id }

    page = Nokogiri::HTML5(response.body)
    expect(page.css(".ck-cmp-score .ck-badge").map(&:text)).to eq(%w[Fail Pass])
    expect(page.at_css(".ck-cmp-delta").text.squish).to eq("Fixed")
  end
end
