require "rails_helper"

RSpec.describe "CompletionKit dashboard dismissals", type: :request do
  let(:base_path) { "/completion_kit/dashboard_dismissals" }

  def dismiss(record)
    post base_path,
         params: { dashboard_dismissal: { dismissable_type: record.class.name, dismissable_id: record.id } },
         as: :turbo_stream
  end

  it "dismisses a metric, snapshotting its window average as the baseline" do
    metric = create(:completion_kit_metric)
    create(:completion_kit_review, response: create(:completion_kit_response), metric: metric, ai_score: 3.0)

    expect { dismiss(metric) }.to change(CompletionKit::DashboardDismissal, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(CompletionKit::DashboardDismissal.last.baseline_score).to eq(3.0)
  end

  it "dismisses a failed run with no baseline score" do
    run = create(:completion_kit_run, status: "failed")

    dismiss(run)

    expect(response).to have_http_status(:ok)
    expect(CompletionKit::DashboardDismissal.last.baseline_score).to be_nil
  end

  it "rejects an unsupported dismissable type" do
    dataset = create(:completion_kit_dataset)
    expect { dismiss(dataset) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "un-dismisses a record on destroy" do
    dismissal = CompletionKit::DashboardDismissal.create!(dismissable: create(:completion_kit_run))

    expect { delete "#{base_path}/#{dismissal.id}", as: :turbo_stream }
      .to change(CompletionKit::DashboardDismissal, :count).by(-1)
    expect(response).to have_http_status(:ok)
  end
end
