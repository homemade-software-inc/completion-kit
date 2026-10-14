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

  def pip(html, label)
    Nokogiri::HTML5(html).at_css("[role=img][aria-label='#{label}']")
  end

  it "shows a row's verdict and its score as a whole percentage on the run page" do
    run, = scored_run(0.5)

    get "/completion_kit/runs/#{run.id}"

    expect(pip(response.body, "Codes Fail 50%")["class"]).to include("ck-metric-pip--low")
    expect(pip_labels(response.body)).to include("Codes Fail 50%")
  end

  it "colours a passing list check's pip by its verdict, not by how far its score is from 1" do
    run, = scored_run(0.8, passed: true)

    get "/completion_kit/runs/#{run.id}"

    expect(pip(response.body, "Codes Pass 80%")["class"]).to include("ck-metric-pip--high")
  end

  it "rounds a list score the same way on the response row, the status panel and the runs list" do
    run, = scored_run(0.575)

    get "/completion_kit/runs/#{run.id}"
    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("#run_status_panel").css(".ck-metric-pip__label").map { |node| node.text.squish }).to include("Codes 58%")
    expect(pip_labels(response.body)).to include("Codes Fail 58%")

    get "/completion_kit/runs"
    expect(pip_labels(response.body)).to include("Codes 58%")
  end

  it "shows a list check's score beside its verdict on the response page" do
    run, row = scored_run(0.8, passed: true)

    get "/completion_kit/runs/#{run.id}/responses/#{row.id}"

    expect(Nokogiri::HTML5(response.body).css(".ck-review-card .ck-badge").map(&:text)).to include("Pass 80%")
  end

  it "shows the run's average score as a percentage in the status panel, coloured by its pass rate" do
    run, = scored_run(0.8, passed: true)

    get "/completion_kit/runs/#{run.id}"

    panel = Nokogiri::HTML5(response.body).at_css("#run_status_panel")
    codes = panel.css(".ck-metric-pip").find { |node| node.text.squish == "Codes 80%" }
    expect(codes["class"]).to include("ck-metric-pip--high")
  end

  it "shows the average score in the runs list the way the status panel does" do
    scored_run(0.5)

    get "/completion_kit/runs"

    expect(pip(response.body, "Codes average score 50%, 0% pass rate")["class"]).to include("ck-metric-pip--low")
    expect(pip_labels(response.body)).to include("Codes 50%")
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

  def compare(left, right)
    get "/completion_kit/runs/#{left.id}/compare", params: { with: right.id }
    page = Nokogiri::HTML5(response.body)
    [page.css(".ck-cmp-score .ck-badge").map(&:text), page.at_css(".ck-cmp-delta")]
  end

  it "shows a score that moved between runs even when the verdict did not" do
    left, = scored_run(0.5)
    right, = scored_run(0.8333)

    badges, delta = compare(left, right)

    expect(badges).to eq(["Fail 50%", "Fail 83%"])
    expect(delta.text.squish).to eq("▲+33%")
  end

  it "marks a list check whose verdict flipped as Fixed or Broke beside the score change" do
    left, = scored_run(0.5)
    right, = scored_run(0.8333, passed: true)

    badges, delta = compare(left, right)
    expect(badges).to eq(["Fail 50%", "Pass 83%"])
    expect(delta.css(".ck-delta").map(&:text)).to eq(["Fixed", "▲+33%"])

    badges, delta = compare(right, left)
    expect(badges).to eq(["Pass 83%", "Fail 50%"])
    expect(delta.css(".ck-delta").map(&:text)).to eq(["Broke", "▼-33%"])
  end

  it "works the score change out from the percentages it shows" do
    left, = scored_run(0.505)
    right, = scored_run(0.835)

    badges, delta = compare(left, right)

    expect(badges).to eq(["Fail 51%", "Fail 84%"])
    expect(delta.text.squish).to eq("▲+33%")
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
