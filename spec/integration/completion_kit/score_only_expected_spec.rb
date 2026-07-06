require "rails_helper"

RSpec.describe "Score-only run graded against per-row expected_output", type: :model do
  include ActiveJob::TestHelper

  before do
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_status_header)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_actions)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_sort_toolbar)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_clear_responses)
  end

  let(:dataset) do
    create(:completion_kit_dataset, csv_data: <<~CSV)
      id,input,actual_output,expected_output
      "911-carreraT-2019-vin.jpg","VIN plate photo","WP0AA2A98KS103927","WP0AA2A98KS103927"
      "911-turbo-2011-vin-windshield.jpg","VIN plate photo (degraded)","WP0CD2A91BS773674","WP0CD2A91BS773674"
      "911-carrera-2014-vin-doorjamb.jpg","VIN plate photo","wp0aa2a97es107665","WP0AA2A97ES107665"
      "miss-2020.jpg","VIN plate photo","","4S4BSANC7L3241589"
    CSV
  end

  let(:metric) do
    create(:completion_kit_metric, :check,
      name: "VIN exact match",
      check_config: { "check_kind" => "equals", "compare_to" => "expected", "trim" => true, "case_sensitive" => false })
  end

  def build_run
    CompletionKit::Run.create!(prompt: nil, dataset: dataset, name: "baseline", output_column: "actual_output").tap do |run|
      run.replace_metrics!([metric.id])
    end
  end

  it "grades a blank cell in the graded column as a failed row instead of crashing" do
    run = build_run

    expect(run.start!).to be(true), -> { "start! failed: #{run.reload.failure_summary}" }
    perform_enqueued_jobs

    run.reload
    expect(run.status).to eq("completed")
    expect(run.responses.count).to eq(4)
    passes = run.responses.order(:row_index).map { |r| r.reviews.first&.passed }
    expect(passes).to eq([true, true, true, false])
    blank_review = run.responses.order(:row_index).last.reviews.first
    expect(blank_review.ai_feedback).to include("4S4BSANC7L3241589")
  end

  it "fails the run with a row-scoped summary when a response cannot be built" do
    run = build_run
    invalid = CompletionKit::Response.new
    invalid.errors.add(:base, "boom")
    allow(run.responses).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(invalid))

    expect(run.start!).to be(false)

    run.reload
    expect(run.status).to eq("failed")
    expect(run.failure_summary).to eq("Row 1: boom")
    expect(run.responses.count).to eq(0)
  end

  it "fails the run with the bare validation message when the failure is not row-scoped" do
    run = build_run
    invalid = CompletionKit::Run.new
    invalid.errors.add(:base, "run invalid")
    allow(run).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(invalid))

    expect(run.start!).to be(false)

    run.reload
    expect(run.status).to eq("failed")
    expect(run.failure_summary).to eq("run invalid")
  end

  it "grades against a custom answer-key column when expected_column is set" do
    custom = create(:completion_kit_dataset, csv_data: <<~CSV)
      input,actual_output,true_vin
      "photo a","WP0AA2A98KS103927","WP0AA2A98KS103927"
      "photo b","NOPE","WP0CD2A91BS773674"
    CSV
    run = CompletionKit::Run.create!(prompt: nil, dataset: custom, name: "custom key",
                                     output_column: "actual_output", expected_column: "true_vin")
    run.replace_metrics!([metric.id])

    expect(run.start!).to be(true), -> { "start! failed: #{run.reload.failure_summary}" }
    perform_enqueued_jobs

    responses = run.reload.responses.order(:row_index)
    expect(responses.map(&:expected_output)).to eq(%w[WP0AA2A98KS103927 WP0CD2A91BS773674])
    expect(responses.map { |r| r.reviews.first.passed }).to eq([true, false])
  end
end
