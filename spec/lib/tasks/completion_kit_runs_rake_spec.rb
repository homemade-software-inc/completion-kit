require "rails_helper"
require "rake"

RSpec.describe "completion_kit:mark_interrupted_runs_failed", type: :task do
  before(:all) do
    Rake.application = Rake::Application.new
    Rake.application.rake_require("tasks/completion_kit_runs", [File.expand_path("../../../lib", __dir__)])
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task["completion_kit:mark_interrupted_runs_failed"] }

  before { task.reenable }

  it "marks running runs as failed with the deploy-interruption summary" do
    running = create(:completion_kit_run, status: "running")
    completed = create(:completion_kit_run, status: "completed")

    expect { task.invoke }.to output(/Marked 1 runs as failed/).to_stdout

    expect(running.reload.status).to eq("failed")
    expect(running.reload.failure_summary).to eq("Interrupted by deploy")
    expect(completed.reload.status).to eq("completed")
  end

  it "marks every running run as failed even when the host tenant_scope matches nothing without a tenant" do
    running = create(:completion_kit_run, status: "running")
    pending_run = create(:completion_kit_run, status: "pending")
    completed = create(:completion_kit_run, status: "completed")
    failed = create(:completion_kit_run, status: "failed")
    configure_tenant_scope

    expect { task.invoke }.to output("Marked 1 runs as failed.\n").to_stdout

    reloaded = CompletionKit::Run.unscoped.where(id: [running, pending_run, completed, failed].map(&:id)).index_by(&:id)
    expect(reloaded[running.id].status).to eq("failed")
    expect(reloaded[running.id].failure_summary).to eq("Interrupted by deploy")
    expect(reloaded[pending_run.id].status).to eq("pending")
    expect(reloaded[completed.id].status).to eq("completed")
    expect(reloaded[failed.id].status).to eq("failed")
  end

  it "is a no-op when no runs are in flight" do
    expect { task.invoke }.to output("Marked 0 runs as failed.\n").to_stdout
  end
end
