require "rails_helper"
require "faraday"

RSpec.describe CompletionKit::Run, type: :model do
  before do
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_status_header)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_actions)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_sort_toolbar)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_clear_responses)
  end

  it "computes the status-panel summaries in one query regardless of run size (no N+1)" do
    metric = create(:completion_kit_metric)
    run = create(:completion_kit_run)
    run.replace_metrics!([metric.id])
    6.times do |i|
      response = create(:completion_kit_response, run: run, status: "succeeded", row_index: i)
      create(:completion_kit_review, response: response, metric: metric, metric_name: "Quality", status: "succeeded", ai_score: 4.0)
    end

    fresh = CompletionKit::Run.find(run.id)
    count = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      payload = ActiveSupport::Notifications::Event.new(*args).payload
      count += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/) || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/i)
    end
    fresh.avg_score
    fresh.metric_averages
    fresh.check_pass_rate
    ActiveSupport::Notifications.unsubscribe(sub)

    expect(count).to eq(1)
  end

  describe "on_run_created host callback" do
    after { CompletionKit.config.on_run_created = nil }

    it "invokes the configured callback once per create with the persisted run" do
      observed = []
      CompletionKit.config.on_run_created = ->(run) { observed << run.id }

      run = create(:completion_kit_run)
      run.update!(name: "renamed")

      expect(observed).to eq([run.id])
    end

    it "does nothing when no callback is configured" do
      expect { create(:completion_kit_run) }.not_to raise_error
    end

    it "reports a raising callback and still creates the run" do
      CompletionKit.config.on_run_created = ->(_run) { raise "host meter down" }
      expect(Rails.error).to receive(:report).with(
        an_instance_of(RuntimeError), hash_including(handled: true)
      )

      expect { create(:completion_kit_run) }.to change(CompletionKit::Run, :count).by(1)
    end
  end

  describe "on_run_started host callback" do
    after { CompletionKit.config.on_run_started = nil }

    it "fires when a run transitions into running" do
      observed = []
      CompletionKit.config.on_run_started = ->(run) { observed << run.id }

      run = create(:completion_kit_run)
      run.update!(status: "running")

      expect(observed).to eq([run.id])
    end

    it "does not fire on an update that leaves the status unchanged" do
      observed = []
      CompletionKit.config.on_run_started = ->(run) { observed << run.id }

      create(:completion_kit_run).update!(name: "renamed")

      expect(observed).to be_empty
    end

    it "does not fire on a status change to something other than running" do
      observed = []
      CompletionKit.config.on_run_started = ->(run) { observed << run.id }

      run = create(:completion_kit_run, status: "running")
      run.update!(status: "completed")

      expect(observed).to be_empty
    end

    it "does nothing when no callback is configured" do
      expect { create(:completion_kit_run).update!(status: "running") }.not_to raise_error
    end

    it "reports a raising callback and still commits the transition" do
      CompletionKit.config.on_run_started = ->(_run) { raise "host meter down" }
      expect(Rails.error).to receive(:report).with(
        an_instance_of(RuntimeError), hash_including(handled: true)
      )

      run = create(:completion_kit_run)
      run.update!(status: "running")

      expect(run.reload.status).to eq("running")
    end
  end

  describe "expected_column (answer-key override)" do
    let(:prompt) { create(:completion_kit_prompt, template: "Static prompt") }
    let(:dataset) { create(:completion_kit_dataset, csv_data: "input,true_vin\nphoto,WP0AA2A98KS103927\n") }

    it "is valid when blank even with a dataset" do
      run = build(:completion_kit_run, prompt: prompt, dataset: dataset, expected_column: nil)
      expect(run).to be_valid
    end

    it "is valid when it names a real dataset column" do
      run = build(:completion_kit_run, prompt: prompt, dataset: dataset, expected_column: "true_vin")
      expect(run).to be_valid
    end

    it "is invalid when it names a column the dataset does not have" do
      run = build(:completion_kit_run, prompt: prompt, dataset: dataset, expected_column: "gold")
      expect(run).not_to be_valid
      expect(run.errors[:expected_column].join).to include("is not a column")
    end

    it "is exposed in as_json" do
      run = create(:completion_kit_run, prompt: prompt, dataset: dataset, expected_column: "true_vin")
      expect(run.as_json[:expected_column]).to eq("true_vin")
    end
  end

  describe "prompt and dataset references outside the tenant scope" do
    let!(:foreign_prompt) { create(:completion_kit_prompt, template: "Static prompt") }
    let!(:foreign_dataset) { create(:completion_kit_dataset) }
    let(:own_prompt) { create(:completion_kit_prompt) }
    let(:own_dataset) { create(:completion_kit_dataset, csv_data: "content,audience\nnotes,devs\n") }

    before { hide_outside_tenant(foreign_prompt, foreign_dataset) }

    it "rejects a prompt the tenant cannot see without treating the run as score-only" do
      run = described_class.new(name: "Cross", prompt_id: foreign_prompt.id, dataset_id: own_dataset.id)

      expect(run).not_to be_valid
      expect(run.errors.full_messages).to eq(["Prompt not found"])
    end

    it "rejects a dataset the tenant cannot see without asking for a dataset" do
      run = described_class.new(name: "Cross", prompt_id: own_prompt.id, dataset_id: foreign_dataset.id)

      expect(run).not_to be_valid
      expect(run.errors.full_messages).to eq(["Dataset not found"])
    end

    it "rejects both references at once" do
      run = described_class.new(name: "Cross", prompt_id: foreign_prompt.id, dataset_id: foreign_dataset.id)

      expect(run).not_to be_valid
      expect(run.errors.full_messages).to eq(["Prompt not found", "Dataset not found"])
    end

    it "answers an id that exists in no tenant the same way" do
      missing_prompt = CompletionKit::Prompt.unscoped.maximum(:id) + 100
      missing_dataset = CompletionKit::Dataset.unscoped.maximum(:id) + 100
      run = described_class.new(name: "Cross", prompt_id: missing_prompt, dataset_id: missing_dataset)

      expect(run).not_to be_valid
      expect(run.errors.full_messages).to eq(["Prompt not found", "Dataset not found"])
    end

    it "writes no row when created on another tenant's prompt over a dataset that would pass as score-only" do
      scoring = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")

      expect {
        described_class.create(name: "Cross", prompt_id: foreign_prompt.id, dataset_id: scoring.id)
      }.not_to change { described_class.unscoped.count }
    end

    it "writes no row when created on another tenant's dataset under a prompt without variables" do
      static = create(:completion_kit_prompt, template: "Static prompt")

      expect {
        described_class.create(name: "Cross", prompt_id: static.id, dataset_id: foreign_dataset.id)
      }.not_to change { described_class.unscoped.count }
    end

    it "rejects an update that points an existing run at another tenant's dataset" do
      run = create(:completion_kit_run, prompt: own_prompt, dataset: own_dataset)

      expect(run.update(dataset_id: foreign_dataset.id)).to be(false)
      expect(run.errors.full_messages).to eq(["Dataset not found"])
      expect(run.reload.dataset_id).to eq(own_dataset.id)
    end

    it "rejects an update that points an existing run at another tenant's prompt" do
      run = create(:completion_kit_run, prompt: own_prompt, dataset: own_dataset)

      expect(run.update(prompt_id: foreign_prompt.id)).to be(false)
      expect(run.errors.full_messages).to eq(["Prompt not found"])
      expect(run.reload.prompt_id).to eq(own_prompt.id)
    end

    it "still saves an update that leaves the references alone" do
      static = create(:completion_kit_prompt, template: "Static prompt")
      run = create(:completion_kit_run, prompt: static, dataset: own_dataset)
      hide_outside_tenant(own_dataset)

      expect(run.reload.update(name: "Renamed")).to be(true)
    end

    it "still accepts a run that clears its prompt to score existing outputs" do
      scoring = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")
      run = described_class.new(name: "Scoring", prompt_id: "", dataset_id: scoring.id)

      expect(run).to be_valid
    end

    it "refuses to rerun a run whose prompt sits in another tenant" do
      scoring = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")
      reset_tenant_scope
      legacy = create(:completion_kit_run, prompt: foreign_prompt, dataset: scoring)
      hide_outside_tenant(foreign_prompt, foreign_dataset)

      expect { legacy.reload.rerun! }.to raise_error(ActiveRecord::RecordInvalid, /Prompt not found/)
      expect(described_class.unscoped.count).to eq(1)
    end
  end

  describe "#replace_metrics!" do
    let(:metric) { create(:completion_kit_metric) }
    let(:run) { create(:completion_kit_run) }

    before { run.replace_metrics!([metric.id]) }

    it "leaves the metrics alone when given nil" do
      run.replace_metrics!(nil)

      expect(run.run_metrics.pluck(:metric_id)).to eq([metric.id])
    end

    it "attaches a repeated id once" do
      other = create(:completion_kit_metric)

      run.replace_metrics!([other.id, other.id.to_s, "", metric.id, other.id])

      expect(run.run_metrics.pluck(:metric_id, :position)).to eq([[other.id, 1], [metric.id, 2]])
    end

    it "clears the metrics when given an empty list" do
      run.replace_metrics!([])

      expect(run.run_metrics).to be_empty
    end
  end

  describe "#selected_metric_ids" do
    let(:metric) { create(:completion_kit_metric) }
    let(:other) { create(:completion_kit_metric) }
    let(:run) { create(:completion_kit_run) }

    before { run.replace_metrics!([metric.id]) }

    it "reads the saved metrics when no selection is assigned" do
      expect(run.selected_metric_ids).to eq([metric.id])
    end

    it "reads a pending selection as unique integers" do
      run.selected_metric_ids = ["", other.id.to_s, other.id.to_s]

      expect(run.selected_metric_ids).to eq([other.id])
    end

    it "keeps the pending selection after a failed save" do
      expect(run.update(judge_temperature: 5, selected_metric_ids: [other.id.to_s])).to be(false)

      expect(run.selected_metric_ids).to eq([other.id])
      expect(run.run_metrics.pluck(:metric_id)).to eq([metric.id])
    end

    it "reads the saved metrics once the selection is attached" do
      run.update!(selected_metric_ids: [other.id.to_s])

      expect(run.selected_metric_ids).to eq([other.id])
      expect(run.run_metrics.pluck(:metric_id)).to eq([other.id])
    end

    it "still attaches the selection on the next save when attaching it raised" do
      calls = 0
      allow(run).to receive(:replace_metrics!).and_wrap_original do |original, ids|
        calls += 1
        raise ActiveRecord::Rollback if calls == 1

        original.call(ids)
      end

      run.selected_metric_ids = [other.id]
      expect(run.save).to be_falsey
      expect(run.run_metrics.pluck(:metric_id)).to eq([metric.id])

      expect(run.save).to be(true)
      expect(run.run_metrics.pluck(:metric_id)).to eq([other.id])
    end
  end

  describe "metric ids outside the tenant scope" do
    let(:static_prompt) { create(:completion_kit_prompt, template: "Static prompt") }
    let(:own_metric) { create(:completion_kit_metric, name: "Own") }
    let(:second_metric) { create(:completion_kit_metric, name: "Second") }
    let!(:foreign_metric) { create(:completion_kit_metric, name: "Foreign") }

    before { hide_outside_tenant(foreign_metric) }

    it "rejects a metric the tenant cannot see before writing the run" do
      run = described_class.new(name: "Cross", prompt: static_prompt, selected_metric_ids: [own_metric.id, foreign_metric.id])

      expect(run.save).to be(false)
      expect(run.errors.full_messages).to eq(["Metrics include one that isn't available"])
      expect(described_class.unscoped.count).to eq(0)
      expect(CompletionKit::RunMetric.unscoped.count).to eq(0)
    end

    it "rejects a metric id that exists in no tenant" do
      missing = CompletionKit::Metric.unscoped.maximum(:id) + 100
      run = described_class.new(name: "Cross", prompt: static_prompt, selected_metric_ids: [missing.to_s])

      expect(run).not_to be_valid
      expect(run.errors.full_messages).to eq(["Metrics include one that isn't available"])
    end

    it "keeps the existing metrics when an update points at another tenant's metric" do
      run = create(:completion_kit_run)
      run.replace_metrics!([own_metric.id])

      expect(run.update(name: "Renamed", selected_metric_ids: [foreign_metric.id])).to be(false)
      expect(run.errors.full_messages).to eq(["Metrics include one that isn't available"])
      expect(run.reload.name).not_to eq("Renamed")
      expect(run.run_metrics.pluck(:metric_id)).to eq([own_metric.id])
    end

    it "attaches the selected metrics in order once the run saves" do
      run = described_class.create!(name: "Mine", prompt: static_prompt, selected_metric_ids: ["", second_metric.id.to_s, own_metric.id.to_s])

      expect(run.run_metrics.pluck(:metric_id, :position)).to eq([[second_metric.id, 1], [own_metric.id, 2]])
    end

    it "replaces the metrics on update and only once" do
      run = create(:completion_kit_run)
      run.replace_metrics!([own_metric.id])

      run.update!(selected_metric_ids: [second_metric.id])
      run.run_metrics.update_all(position: 7)
      run.update!(name: "Renamed")

      expect(run.run_metrics.pluck(:metric_id, :position)).to eq([[second_metric.id, 7]])
    end

    it "leaves the metrics alone when no selection is given" do
      run = create(:completion_kit_run)
      run.replace_metrics!([own_metric.id])

      expect(run.update(name: "Renamed", selected_metric_ids: nil)).to be(true)
      expect(run.run_metrics.pluck(:metric_id)).to eq([own_metric.id])
    end

    it "carries the metrics over in order on rerun" do
      create(:completion_kit_provider_credential)
      run = create(:completion_kit_run)
      run.replace_metrics!([second_metric.id, own_metric.id])

      expect(run.rerun!.run_metrics.pluck(:metric_id)).to eq([second_metric.id, own_metric.id])
    end

    it "refuses to rerun a run that carries another tenant's metric" do
      reset_tenant_scope
      create(:completion_kit_provider_credential)
      legacy = create(:completion_kit_run)
      legacy.replace_metrics!([own_metric.id, foreign_metric.id])
      hide_outside_tenant(foreign_metric)

      expect { legacy.reload.rerun! }.to raise_error(ActiveRecord::RecordInvalid, /Metrics include one that isn't available/)
      expect(described_class.unscoped.count).to eq(1)
    end
  end

  describe "RunMetric metric outside the tenant scope" do
    it "rejects a metric the tenant cannot see" do
      run = create(:completion_kit_run)
      foreign_metric = create(:completion_kit_metric)
      hide_outside_tenant(foreign_metric)

      run_metric = CompletionKit::RunMetric.new(run: run, metric_id: foreign_metric.id, position: 1)

      expect(run_metric).not_to be_valid
      expect(run_metric.errors.full_messages).to eq(["Metric must exist"])
    end
  end

  describe ".display_scoped" do
    it "returns all runs when no runs_display_scope is configured" do
      recent = create(:completion_kit_run)
      old = create(:completion_kit_run, created_at: 90.days.ago)
      expect(CompletionKit::Run.display_scoped).to match_array([recent, old])
    end

    it "applies the configured callable to the current relation" do
      recent = create(:completion_kit_run)
      create(:completion_kit_run, created_at: 90.days.ago)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      expect(CompletionKit::Run.display_scoped).to eq([recent])
    ensure
      CompletionKit.config.runs_display_scope = nil
    end

    it "preserves the receiving relation's own conditions while applying the filter" do
      keep = create(:completion_kit_run)
      create(:completion_kit_run)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      expect(CompletionKit::Run.where(id: keep.id).display_scoped).to eq([keep])
    ensure
      CompletionKit.config.runs_display_scope = nil
    end

    it "preserves an association scope when filtering a dataset's runs" do
      dataset = create(:completion_kit_dataset)
      mine = create(:completion_kit_run, dataset: dataset)
      create(:completion_kit_run)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      expect(dataset.runs.display_scoped).to eq([mine])
    ensure
      CompletionKit.config.runs_display_scope = nil
    end

    it "exposes visible_run_ids as a subquery usable by child records" do
      recent = create(:completion_kit_run)
      create(:completion_kit_run, created_at: 90.days.ago)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      expect(CompletionKit::Run.where(id: CompletionKit::Run.visible_run_ids)).to eq([recent])
    ensure
      CompletionKit.config.runs_display_scope = nil
    end
  end

  describe "#regrade!" do
    let(:run) { create(:completion_kit_run, judge_model: "gpt-4.1") }
    let(:metric) { create(:completion_kit_metric) }

    before do
      allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
      allow(CompletionKit::JudgeReviewJob).to receive(:perform_later)
      allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true)
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
    end

    it "resets each succeeded response's review back to pending and re-enqueues JudgeReviewJob for every metric x response" do
      response_row = create(:completion_kit_response, run: run, status: "succeeded", response_text: "scored")
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      review = create(:completion_kit_review, response: response_row, metric: metric, metric_name: metric.name, ai_score: 5, status: "succeeded", metric_version_id: v1.id)

      expect(run.regrade!).to be(true)

      review.reload
      expect(review.status).to eq("pending")
      expect(review.ai_score).to be_nil
      expect(review.metric_version_id).to be_nil
      expect(run.reload.status).to eq("running")
      expect(CompletionKit::JudgeReviewJob).to have_received(:perform_later).with(response_row.id, metric.id, run.id)
    end

    it "clears a stale judge-temperature-refused flag, because the scores are about to be replaced" do
      create(:completion_kit_response, run: run, status: "succeeded", response_text: "scored")
      run.update_columns(judge_temperature_ignored: true)
      expect(run.nondeterministic_judge?).to be(true)

      expect(run.regrade!).to be(true)

      expect(run.reload.judge_temperature_ignored).to be(false)
      expect(run.nondeterministic_judge?).to be(false)
    end

    it "returns false and does no work when the run has no eligible succeeded responses" do
      expect(run.regrade!).to be(false)
      expect(CompletionKit::JudgeReviewJob).not_to have_received(:perform_later)
    end

    it "fires on_run_started because regrade! transitions the run back to running" do
      response_row = create(:completion_kit_response, run: run, status: "succeeded", response_text: "scored")
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      create(:completion_kit_review, response: response_row, metric: metric, metric_name: metric.name, ai_score: 5, status: "succeeded", metric_version_id: v1.id)
      observed = []
      CompletionKit.config.on_run_started = ->(r) { observed << r.id }

      expect(run.regrade!).to be(true)

      expect(observed).to eq([run.id])
    ensure
      CompletionKit.config.on_run_started = nil
    end

    it "returns false when the run has no metrics attached" do
      bare_run = create(:completion_kit_run, judge_model: "gpt-4.1")
      create(:completion_kit_response, run: bare_run, status: "succeeded", response_text: "ok")
      expect(bare_run.regrade!).to be(false)
    end

    it "returns false when no judge_model is configured on the run" do
      judgeless_run = create(:completion_kit_run, judge_model: nil)
      CompletionKit::RunMetric.create!(run: judgeless_run, metric: metric, position: 1)
      create(:completion_kit_response, run: judgeless_run, status: "succeeded", response_text: "ok")
      expect(judgeless_run.regrade!).to be(false)
    end
  end

  describe "#stale_review_summary" do
    it "returns an empty hash when there are no reviews" do
      run = create(:completion_kit_run)
      expect(run.stale_review_summary).to eq({})
    end

    it "returns an empty hash when all reviews are stamped against the current metric_version" do
      run = create(:completion_kit_run)
      metric = create(:completion_kit_metric)
      current = CompletionKit::MetricVersion.ensure_current_for(metric)
      response = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: 4, metric_version_id: current.id)
      expect(run.stale_review_summary).to eq({})
    end

    it "returns the metric, stale labels, current label, and stale count when a review's metric_version is superseded" do
      run = create(:completion_kit_run)
      metric = create(:completion_kit_metric)
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      response = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: 4, metric_version_id: v1.id)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
      v2.publish!
      summary = run.stale_review_summary
      expect(summary[metric.id][:metric_name]).to eq(metric.name)
      expect(summary[metric.id][:current_label]).to eq("v2")
      expect(summary[metric.id][:scored_labels]).to eq(["v1"])
      expect(summary[metric.id][:stale_count]).to eq(1)
    end

    it "skips reviews missing a metric_version stamp or a current published version" do
      run = create(:completion_kit_run)
      metric = create(:completion_kit_metric)
      response = create(:completion_kit_response, run: run)
      review = build(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: 4, metric_version: nil)
      review.save(validate: false)
      expect(run.stale_review_summary).to eq({})
    end

    it "skips reviews whose metric_version_id points at a row that no longer exists" do
      run = create(:completion_kit_run)
      metric = create(:completion_kit_metric)
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
      v2.publish!
      response = create(:completion_kit_response, run: run)
      ghost_review = create(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: 4, metric_version_id: v1.id)
      v1.delete
      expect(run.stale_review_summary).to eq({})
    end

    it "skips reviews on a metric that has no current published version" do
      run = create(:completion_kit_run)
      metric = create(:completion_kit_metric)
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      response = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: 4, metric_version_id: v1.id)
      CompletionKit::MetricVersion.where(metric_id: metric.id).update_all(current: false)
      expect(run.stale_review_summary).to eq({})
    end
  end

  describe "#metrics" do
    it "returns empty array when no metrics associated" do
      run = create(:completion_kit_run)
      expect(run.metrics).to eq([])
    end

    it "returns associated metrics ordered by position" do
      run = create(:completion_kit_run)
      m1 = create(:completion_kit_metric, name: "Second")
      m2 = create(:completion_kit_metric, name: "First")
      CompletionKit::RunMetric.create!(run: run, metric: m1, position: 2)
      CompletionKit::RunMetric.create!(run: run, metric: m2, position: 1)
      expect(run.metrics.map(&:name)).to eq(["First", "Second"])
    end
  end

  describe "broadcast helpers" do
    let(:prompt) { create(:completion_kit_prompt) }
    let(:run) { create(:completion_kit_run, prompt: prompt) }

    before do
      allow(run).to receive(:broadcast_ui).and_call_original
      allow(run).to receive(:broadcast_progress).and_call_original
      allow(run).to receive(:broadcast_response).and_call_original
      allow(run).to receive(:broadcast_response_update).and_call_original
      allow(run).to receive(:broadcast_status_header).and_call_original
      allow(run).to receive(:broadcast_actions).and_call_original
      allow(run).to receive(:broadcast_sort_toolbar).and_call_original
      allow(run).to receive(:broadcast_replace_to)
      allow(run).to receive(:broadcast_append_to)
    end

    it "broadcast_ui dispatches to the four sub-broadcasts" do
      run.broadcast_ui
      expect(run).to have_received(:broadcast_progress)
      expect(run).to have_received(:broadcast_status_header).at_least(:once)
      expect(run).to have_received(:broadcast_actions)
      expect(run).to have_received(:broadcast_sort_toolbar)
    end

    it "broadcast_progress calls broadcast_replace_to with run_status_panel target" do
      run.send(:broadcast_progress)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "run_status_panel")
      )
    end

    it "broadcast_response calls broadcast_append_to with run_responses target" do
      response = run.responses.create!(response_text: "test")
      run.send(:broadcast_response, response)
      expect(run).to have_received(:broadcast_append_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "run_responses")
      )
    end

    it "broadcast_response_update calls broadcast_replace_to with response target" do
      response = run.responses.create!(response_text: "test")
      run.broadcast_response_update(response)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "response_#{response.id}")
      ).at_least(:once)
    end

    it "broadcast_status_header calls broadcast_replace_to with run_status_header target" do
      run.send(:broadcast_status_header)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "run_status_header")
      )
    end

    it "broadcast_actions calls broadcast_replace_to with run_actions target" do
      run.send(:broadcast_actions)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "run_actions")
      )
    end

    it "broadcast_sort_toolbar calls broadcast_replace_to with run_sort_toolbar target" do
      allow(run).to receive(:broadcast_sort_toolbar).and_call_original
      run.send(:broadcast_sort_toolbar)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "run_sort_toolbar")
      )
    end

    it "broadcast_clear_responses calls broadcast_replace_to with run_responses target" do
      allow(run).to receive(:broadcast_clear_responses).and_call_original
      run.send(:broadcast_clear_responses)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "run_responses")
      )
    end
  end

  describe "#start!" do
    let(:prompt) { create(:completion_kit_prompt, template: "Static prompt with no variables") }
    let(:client) { instance_double(CompletionKit::LlmClient, configured?: true, configuration_errors: []) }

    before do
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
      allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
    end

    it "clears both temperature-ignored flags, because generation and judging are about to be redone" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil, status: "failed")
      run.update_columns(temperature_ignored: true, judge_temperature_ignored: true)

      expect(start_run!(run)).to be true

      expect(run.reload.temperature_ignored).to be(false)
      expect(run.judge_temperature_ignored).to be(false)
    end

    it "creates pending Responses and enqueues GenerateRowJob for each row" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil)

      result = start_run!(run)

      expect(result).to be true
      expect(run.responses.count).to eq(1)
      expect(run.responses.first.status).to eq("pending")
      expect(CompletionKit::GenerateRowJob).to have_received(:perform_later).once
    end

    it "inserts responses in bounded batches so the INSERT statement stays small on large datasets" do
      stub_const("CompletionKit::Run::INSERT_BATCH_SIZE", 2)
      dataset = create(:completion_kit_dataset, csv_data: "input\na\nb\nc\nd\ne\n")
      run = create(:completion_kit_run, prompt: prompt, dataset: dataset)

      batch_sizes = []
      allow(CompletionKit::Response).to receive(:insert_all).and_wrap_original do |orig, rows|
        batch_sizes << rows.size
        orig.call(rows)
      end

      expect(start_run!(run)).to be true
      expect(batch_sizes).to eq([2, 2, 1])
      expect(run.responses.count).to eq(5)
    end

    it "bulk-enqueues the row jobs with a single perform_all_later instead of one enqueue per row" do
      dataset = create(:completion_kit_dataset, csv_data: "input\na\nb\nc\n")
      run = create(:completion_kit_run, prompt: prompt, dataset: dataset)

      start_run!(run)

      expect(ActiveJob).to have_received(:perform_all_later).once
    end

    it "refuses to restart a running run and leaves its responses alone (prevents data loss from a stray POST /generate)" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil, status: "running")
      existing = create(:completion_kit_response, run: run, status: "succeeded")

      result = start_run!(run)

      expect(result).to be false
      expect(CompletionKit::Response.where(id: existing.id)).to exist
      expect(run.reload.failure_summary).to include("Cannot start a run")
    end

    it "refuses to restart a completed run (use rerun instead)" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil, status: "completed")
      existing = create(:completion_kit_response, run: run, status: "succeeded")

      result = start_run!(run)

      expect(result).to be false
      expect(CompletionKit::Response.where(id: existing.id)).to exist
    end

    it "still allows restarting a failed run (Retry button path)" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil, status: "failed")
      result = start_run!(run)
      expect(result).to be true
      expect(run.reload.status).to eq("running")
    end

    it "transitions status to running" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil)

      start_run!(run)

      expect(run.reload.status).to eq("running")
    end

    it "still reports success when the post-start UI broadcast raises (no started run leaks as an API error)" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil)
      allow(run).to receive(:broadcast_ui)
        .and_raise(ActionController::UrlGenerationError.new("missing required keys: [:org_slug]"))

      expect(start_run!(run)).to be(true)
      expect(run.reload.status).to eq("running")
      expect(CompletionKit::GenerateRowJob).to have_received(:perform_later).once
    end

    it "returns false and sets failure_summary when dataset has no rows" do
      dataset = create(:completion_kit_dataset, csv_data: "header\n")
      run = create(:completion_kit_run, prompt: prompt, dataset: dataset)
      allow(CompletionKit::CsvProcessor).to receive(:process_self).and_return([])

      result = start_run!(run)

      expect(result).to be false
      expect(run.reload.status).to eq("failed")
      expect(run.reload.failure_summary).to include("Dataset has no rows")
    end

    it "refuses a header-only dataset before claiming the run, without counting or parsing its rows" do
      dataset = create(:completion_kit_dataset, csv_data: "header\n")
      run = create(:completion_kit_run, prompt: prompt, dataset: dataset)
      sizes = track_csv_reads
      expect_any_instance_of(CompletionKit::Dataset).not_to receive(:row_count)

      expect(run.start!).to be(false)
      expect(run.reload.status).to eq("failed")
      expect(run.failure_summary).to eq("Dataset has no rows")
      expect(sizes).to be_empty
    end

    it "starts a run over a whitespace-led dataset at the upload limit without blank? or a regex over the whole file" do
      dataset = build(:completion_kit_dataset, csv_data: whitespace_led_csv(CompletionKit.config.max_upload_bytes))
      dataset.save!(validate: false)
      run = create(:completion_kit_run, prompt: prompt, dataset: dataset)
      scans = track_string_scans(dataset.csv_data)
      expect_any_instance_of(CompletionKit::Dataset).not_to receive(:row_count)

      expect(run.dataset).to be(dataset)
      expect(run.start!).to be(true)
      expect(run.reload.status).to eq("running")
      expect(scans).to be_empty
    end

    it "leaves a malformed dataset to StartRunJob, which fails the run with the same summary" do
      dataset = create(:completion_kit_dataset, csv_data: "input\n\"unclosed\n")
      run = create(:completion_kit_run, prompt: prompt, dataset: dataset)

      expect(start_run!(run)).to be(true)
      expect(run.reload.status).to eq("failed")
      expect(run.failure_summary).to eq("Dataset has no rows")
    end

    it "returns false and sets failure_summary when LLM client is not configured" do
      bad_client = instance_double(CompletionKit::LlmClient, configured?: false, configuration_errors: ["API key missing"])
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(bad_client)
      run = create(:completion_kit_run, prompt: prompt, dataset: nil)

      result = start_run!(run)

      expect(result).to be false
      expect(run.reload.status).to eq("failed")
      expect(run.reload.failure_summary).to include("LLM API not configured")
    end

    it "returns false without persisting when run is not persisted and LLM is unconfigured" do
      bad_client = instance_double(CompletionKit::LlmClient, configured?: false, configuration_errors: ["API key missing"])
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(bad_client)
      run = build(:completion_kit_run, prompt: prompt, dataset: nil)

      result = start_run!(run)

      expect(result).to be false
      expect(run).not_to be_persisted
    end
  end

  describe "judge-only runs" do
    let(:metric) { create(:completion_kit_metric, name: "Quality") }
    let(:dataset_with_output) do
      create(:completion_kit_dataset, csv_data: "input,actual_output\nWhat is 2+2?,4\nWhat is 1+1?,2\n")
    end
    let(:dataset_without_output) do
      create(:completion_kit_dataset, csv_data: "input,response\nWhat is 2+2?,four\n")
    end

    describe "#judge_only?" do
      it "is true when no prompt is associated" do
        run = build(:completion_kit_run, prompt: nil, dataset: dataset_with_output)
        expect(run.judge_only?).to eq(true)
      end

      it "is false when a prompt is associated" do
        run = build(:completion_kit_run)
        expect(run.judge_only?).to eq(false)
      end
    end

    describe "auto-generated name" do
      it "names an unnamed run after its prompt version and run count" do
        prompt = create(:completion_kit_prompt, name: "Support Reply Generator")
        create(:completion_kit_run, prompt: prompt)
        run = create(:completion_kit_run, prompt: prompt, name: nil)
        expect(run.name).to eq("Support Reply Generator · v1 #2")
      end

      it "leaves a stored name alone when the run is saved again" do
        run = create(:completion_kit_run, name: "Support Reply Generator \u2014 v1 #3")
        run.update!(max_tokens: 200)
        expect(run.reload.name).to eq("Support Reply Generator \u2014 v1 #3")
      end

      it "names an unnamed scoring run after its dataset" do
        dataset = create(:completion_kit_dataset, name: "Tickets", csv_data: "input,actual_output\nhi,hello\n")
        run = create(:completion_kit_run, prompt: nil, dataset: dataset, output_column: "actual_output", name: nil)
        expect(run.name).to eq("Tickets scoring #1")
      end
    end

    describe "validations" do
      it "requires a dataset for a judge-only run" do
        run = build(:completion_kit_run, prompt: nil, dataset: nil)
        expect(run).not_to be_valid
        expect(run.errors[:dataset_id].join).to include("required when scoring existing outputs")
      end

      it "rejects a judge-only run whose output_column is not on the dataset" do
        run = build(:completion_kit_run, prompt: nil, dataset: dataset_without_output, output_column: "actual_output")
        expect(run).not_to be_valid
        expect(run.errors[:output_column].join).to include("is not a column on dataset")
      end

      it "accepts a judge-only run with a valid output_column" do
        run = build(:completion_kit_run, prompt: nil, dataset: dataset_with_output, output_column: "actual_output")
        expect(run).to be_valid
      end

      it "defaults to the actual_output column when output_column is blank" do
        run = build(:completion_kit_run, prompt: nil, dataset: dataset_with_output, output_column: nil)
        expect(run).to be_valid
      end
    end

    describe "#start!" do
      let(:run) do
        run = create(:completion_kit_run, prompt: nil, dataset: dataset_with_output, judge_model: "gpt-4o")
        CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
        run
      end

      before do
        allow(CompletionKit::JudgeReviewJob).to receive(:perform_later)
        allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
        allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
        allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true)
      end

      it "marks every response succeeded with response_text from the output_column and skips GenerateRowJob" do
        result = start_run!(run)

        expect(result).to be true
        expect(run.responses.count).to eq(2)
        expect(run.responses.pluck(:status).uniq).to eq(["succeeded"])
        expect(run.responses.pluck(:response_text)).to match_array(%w[4 2])
        expect(CompletionKit::GenerateRowJob).not_to have_received(:perform_later)
      end

      it "enqueues JudgeReviewJob per response per metric when judging is configured" do
        start_run!(run)

        expect(CompletionKit::JudgeReviewJob).to have_received(:perform_later).twice
      end

      it "skips JudgeReviewJob when no judge is configured but still creates succeeded responses" do
        bare = create(:completion_kit_run, prompt: nil, dataset: dataset_with_output, judge_model: nil)

        start_run!(bare)

        expect(bare.responses.pluck(:status).uniq).to eq(["succeeded"])
        expect(CompletionKit::JudgeReviewJob).not_to have_received(:perform_later)
      end

      it "enqueues RunCompletionCheckJob once" do
        start_run!(run)

        expect(CompletionKit::RunCompletionCheckJob).to have_received(:perform_later).with(run.id)
      end

      it "fails with a summary when the dataset is missing the output_column" do
        mismatched = build(:completion_kit_run, prompt: nil, dataset: dataset_with_output, output_column: "expected_output")
        mismatched.save(validate: false)

        result = start_run!(mismatched)

        expect(result).to be false
        expect(mismatched.reload.status).to eq("failed")
        expect(mismatched.reload.failure_summary).to include("Dataset has no \"expected_output\" column")
      end
    end
  end

  describe "check metric execution" do
    let(:check_metric) do
      create(:completion_kit_metric, :check, check_config: { "check_kind" => "contains", "target" => "response_text", "value" => "ok" })
    end
    let(:llm_metric) { create(:completion_kit_metric, name: "Quality") }

    describe "#llm_judge_configured? and #gradable?" do
      before { allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true) }

      it "llm_judge_configured? is false for a check-only run with a judge_model but no llm metric" do
        run = create(:completion_kit_run, judge_model: "gpt-4o")
        run.run_metrics.create!(metric: check_metric, position: 1)
        expect(run.llm_judge_configured?).to be(false)
        expect(run.gradable?).to be(true)
      end

      it "llm_judge_configured? is true with a judge_model, an llm metric, and a valid model" do
        run = create(:completion_kit_run, judge_model: "gpt-4o")
        run.run_metrics.create!(metric: llm_metric, position: 1)
        expect(run.llm_judge_configured?).to be(true)
        expect(run.gradable?).to be(true)
      end

      it "gradable? is false for an llm-only run with no judge_model" do
        run = create(:completion_kit_run, judge_model: nil)
        run.run_metrics.create!(metric: llm_metric, position: 1)
        expect(run.gradable?).to be(false)
      end
    end

    describe "#start! dispatch" do
      before do
        allow(CompletionKit::JudgeReviewJob).to receive(:perform_later)
        allow(CompletionKit::CheckReviewJob).to receive(:perform_later)
        allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
        allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
        allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true)
      end

      it "dispatches CheckReviewJob (not JudgeReviewJob) for a check-only judge-only run with no judge_model" do
        dataset = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")
        run = create(:completion_kit_run, prompt: nil, dataset: dataset, judge_model: nil)
        run.run_metrics.create!(metric: check_metric, position: 1)

        expect(start_run!(run)).to be(true)
        expect(CompletionKit::CheckReviewJob).to have_received(:perform_later).once
        expect(CompletionKit::JudgeReviewJob).not_to have_received(:perform_later)
        expect(CompletionKit::RunCompletionCheckJob).to have_received(:perform_later).with(run.id)
      end

      it "dispatches both job types for a mixed judge-only run" do
        dataset = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")
        run = create(:completion_kit_run, prompt: nil, dataset: dataset, judge_model: "gpt-4o")
        run.run_metrics.create!(metric: llm_metric, position: 1)
        run.run_metrics.create!(metric: check_metric, position: 2)

        start_run!(run)

        expect(CompletionKit::JudgeReviewJob).to have_received(:perform_later).once
        expect(CompletionKit::CheckReviewJob).to have_received(:perform_later).once
      end
    end

    describe "an input_data-only check run needs no output column" do
      let(:input_check) do
        create(:completion_kit_metric, :check, check_config: { "check_kind" => "valid_json", "target" => "input_data" })
      end
      let(:dataset_no_output) { create(:completion_kit_dataset, csv_data: "input,topic\nhello,greeting\n") }

      before do
        allow(CompletionKit::CheckReviewJob).to receive(:perform_later)
        allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
      end

      it "is valid and starts with succeeded responses carrying nil response_text" do
        run = CompletionKit::Run.new(prompt: nil, dataset: dataset_no_output, name: "input check")
        run.run_metrics.build(metric: input_check, position: 1)

        expect(run).to be_valid
        run.save!

        expect(start_run!(run)).to be(true)
        expect(run.responses.pluck(:status).uniq).to eq(["succeeded"])
        expect(run.responses.first.response_text).to be_nil
        expect(CompletionKit::CheckReviewJob).to have_received(:perform_later).once
      end

      it "regrades despite nil response_text on its responses" do
        run = CompletionKit::Run.new(prompt: nil, dataset: dataset_no_output, name: "input check")
        run.run_metrics.build(metric: input_check, position: 1)
        run.save!
        response_row = create(:completion_kit_response, run: run, status: "succeeded", response_text: nil)

        expect(run.regrade!).to be(true)
        expect(CompletionKit::CheckReviewJob).to have_received(:perform_later).with(response_row.id, input_check.id, run.id)
      end
    end

    describe "#regrade! with checks" do
      before do
        allow(CompletionKit::CheckReviewJob).to receive(:perform_later)
        allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
      end

      it "is gated on gradable?, clears passed, and re-dispatches CheckReviewJob" do
        run = create(:completion_kit_run, judge_model: nil)
        run.run_metrics.create!(metric: check_metric, position: 1)
        response_row = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
        v1 = CompletionKit::MetricVersion.ensure_current_for(check_metric)
        review = response_row.reviews.create!(metric: check_metric, metric_name: check_metric.name,
                                              metric_version_id: v1.id, status: "succeeded", passed: true, ai_score: nil)

        expect(run.regrade!).to be(true)
        expect(review.reload.passed).to be_nil
        expect(review.reload.status).to eq("pending")
        expect(CompletionKit::CheckReviewJob).to have_received(:perform_later).with(response_row.id, check_metric.id, run.id)
      end
    end

    describe "completion ignores an un-gradable llm metric" do
      it "does not count an llm metric with no configured judge in outstanding work" do
        run = create(:completion_kit_run, judge_model: nil, progress_total: 1)
        run.run_metrics.create!(metric: llm_metric, position: 1)
        run.run_metrics.create!(metric: check_metric, position: 2)
        response_row = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
        response_row.reviews.create!(metric: check_metric, metric_name: check_metric.name,
                                    metric_version_id: CompletionKit::MetricVersion.ensure_current_for(check_metric).id,
                                    status: "succeeded", passed: true, ai_score: nil)

        expect(run.outstanding_work_zero?).to be(true)
      end

      it "reports the check as judged_done in progress even though an un-gradable llm metric is attached" do
        run = create(:completion_kit_run, judge_model: nil, progress_total: 1)
        run.run_metrics.create!(metric: llm_metric, position: 1)
        run.run_metrics.create!(metric: check_metric, position: 2)
        response_row = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
        response_row.reviews.create!(metric: check_metric, metric_name: check_metric.name,
                                    metric_version_id: CompletionKit::MetricVersion.ensure_current_for(check_metric).id,
                                    status: "succeeded", passed: true, ai_score: nil)

        expect(run.progress_snapshot[:judged_done]).to eq(1)
      end
    end

    describe "#progress_snapshot with checks" do
      it "counts a succeeded check review as judged_done" do
        run = create(:completion_kit_run, judge_model: nil, progress_total: 1)
        run.run_metrics.create!(metric: check_metric, position: 1)
        response_row = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
        v1 = CompletionKit::MetricVersion.ensure_current_for(check_metric)
        response_row.reviews.create!(metric: check_metric, metric_name: check_metric.name,
                                    metric_version_id: v1.id, status: "succeeded", passed: true, ai_score: nil)

        expect(run.progress_snapshot[:judged_done]).to eq(1)
      end
    end
  end

  describe "#generate_responses!" do
    let(:prompt) { create(:completion_kit_prompt, template: "Static prompt with no variables") }
    let(:client) { instance_double(CompletionKit::LlmClient, configured?: true, configuration_errors: []) }

    before do
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
      allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
    end

    it "delegates to start! and returns true on success" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil)
      result = run.generate_responses!
      expect(result).to be true
    end
  end

  describe "dataset_supplies_prompt_variables validation" do
    let(:prompt_with_vars) { create(:completion_kit_prompt, template: "Hello {{name}}, regarding {{topic}}") }
    let(:prompt_without_vars) { create(:completion_kit_prompt, template: "Static prompt") }

    it "rejects a run when prompt has variables and no dataset is supplied" do
      run = build(:completion_kit_run, prompt: prompt_with_vars, dataset: nil)
      expect(run).not_to be_valid
      expect(run.errors[:dataset_id].join).to include("name").and include("topic")
    end

    it "rejects a run when dataset is missing required columns" do
      dataset = create(:completion_kit_dataset, csv_data: "name,other\nfoo,bar\n")
      run = build(:completion_kit_run, prompt: prompt_with_vars, dataset: dataset)
      expect(run).not_to be_valid
      expect(run.errors[:dataset_id].join).to include("topic")
    end

    it "accepts a run when all variables are present in dataset headers" do
      dataset = create(:completion_kit_dataset, csv_data: "name,topic\nfoo,bar\n")
      run = build(:completion_kit_run, prompt: prompt_with_vars, dataset: dataset)
      expect(run).to be_valid
    end

    it "accepts a run with no dataset when prompt has no variables" do
      run = build(:completion_kit_run, prompt: prompt_without_vars, dataset: nil)
      expect(run).to be_valid
    end

    it "reads only the header row of a dataset at the upload limit, for prompt and scoring-only runs alike" do
      limit = CompletionKit.config.max_upload_bytes
      header = "name,topic,actual_output,expected_output\n"
      body = header + ("a,b,c,d\n" * ((limit - header.bytesize) / 8))
      dataset = create(:completion_kit_dataset, csv_data: body + ("e" * (limit - body.bytesize)))
      sizes = track_csv_reads
      splits = 0
      allow(dataset.csv_data).to receive(:lines).and_wrap_original do |original, *args|
        splits += 1
        original.call(*args)
      end

      expect(dataset.csv_data.bytesize).to eq(limit)
      expect(build(:completion_kit_run, prompt: prompt_with_vars, dataset: dataset, expected_column: "expected_output")).to be_valid
      expect(build(:completion_kit_run, prompt: nil, dataset: dataset, expected_column: "expected_output")).to be_valid
      expect(splits).to eq(0)
      expect(sizes).not_to be_empty
      expect(sizes.max).to eq(header.chomp.bytesize)
    end

    it "never parses a single-line dataset at the upload limit while validating a run" do
      dataset = build(:completion_kit_dataset, csv_data: "name,topic," + ("a," * ((CompletionKit.config.max_upload_bytes - 11) / 2)))
      sizes = track_csv_reads
      run = build(:completion_kit_run, prompt: prompt_with_vars, dataset: dataset, expected_column: "topic")

      expect(run).not_to be_valid
      expect(run.errors[:dataset_id].join).to include("name").and include("topic")
      expect(sizes).to be_empty
    end

    it "never runs blank? or a regex over a whitespace-led dataset at the upload limit while validating a run" do
      dataset = build(:completion_kit_dataset, csv_data: whitespace_led_csv(CompletionKit.config.max_upload_bytes))
      dataset.save!(validate: false)
      scans = track_string_scans(dataset.csv_data)
      sizes = track_csv_reads
      with_prompt = build(:completion_kit_run, prompt: prompt_with_vars, dataset: dataset, expected_column: "expected")
      scoring_only = build(:completion_kit_run, prompt: nil, dataset: dataset, expected_column: "expected")

      expect(dataset.csv_data.bytesize).to eq(CompletionKit.config.max_upload_bytes)
      expect(with_prompt).not_to be_valid
      expect(with_prompt.errors[:dataset_id].join).to include("name").and include("topic")
      expect(with_prompt.errors[:expected_column].join).to include('"expected" is not a column')
      expect(scoring_only).not_to be_valid
      expect(scoring_only.errors[:output_column].join).to include('"actual_output" is not a column')
      expect(scans).to be_empty
      expect(sizes).to all(eq(0))
    end
  end

  describe "#outstanding_work_zero?" do
    let(:prompt) { create(:completion_kit_prompt) }
    let(:metric) { create(:completion_kit_metric) }

    before { allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true) }

    it "returns true when all responses are terminal and no metrics" do
      run = create(:completion_kit_run, prompt: prompt)
      run.responses.create!(status: "succeeded", response_text: "done")
      expect(run.outstanding_work_zero?).to be true
    end

    it "returns false when a response is non-terminal" do
      run = create(:completion_kit_run, prompt: prompt)
      run.responses.create!(status: "pending")
      expect(run.outstanding_work_zero?).to be false
    end

    it "returns false when a response is succeeded but review is non-terminal" do
      run = create(:completion_kit_run, prompt: prompt, judge_model: "gpt-4o")
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
      response = run.responses.create!(status: "succeeded", response_text: "done")
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      response.reviews.create!(metric: metric, status: "pending", metric_name: metric.name, metric_version: v1)
      expect(run.outstanding_work_zero?).to be false
    end

    it "returns true when all responses and reviews are terminal" do
      run = create(:completion_kit_run, prompt: prompt, judge_model: "gpt-4o")
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
      response = run.responses.create!(status: "succeeded", response_text: "done")
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      response.reviews.create!(metric: metric, status: "succeeded", metric_name: metric.name, metric_version: v1)
      expect(run.outstanding_work_zero?).to be true
    end

    it "returns true when metrics exist but all responses failed (no succeeded responses)" do
      run = create(:completion_kit_run, prompt: prompt, judge_model: "gpt-4o")
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
      run.responses.create!(status: "failed")
      expect(run.outstanding_work_zero?).to be true
    end
  end

  describe "#progress_snapshot" do
    let(:prompt) { create(:completion_kit_prompt) }
    let(:metric) { create(:completion_kit_metric) }

    before { allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true) }

    it "returns correct counts for both phases" do
      run = create(:completion_kit_run, prompt: prompt, judge_model: "gpt-4o", progress_total: 3)
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)

      r1 = run.responses.create!(status: "succeeded", response_text: "done")
      run.responses.create!(status: "failed")
      run.responses.create!(status: "pending")

      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      r1.reviews.create!(metric: metric, status: "succeeded", metric_name: metric.name, metric_version: v1)

      snapshot = run.progress_snapshot

      expect(snapshot[:generated_done]).to eq(1)
      expect(snapshot[:generated_failed]).to eq(1)
      expect(snapshot[:generated_total]).to eq(3)
      expect(snapshot[:judged_done]).to eq(1)
      expect(snapshot[:judged_failed]).to eq(0)
      expect(snapshot[:judged_total]).to eq(1)
    end

    it "does not count a row as judged_done until all metric reviews are terminal" do
      metric_a = create(:completion_kit_metric, name: "A")
      metric_b = create(:completion_kit_metric, name: "B")
      run = create(:completion_kit_run, prompt: prompt, judge_model: "gpt-4o", progress_total: 1)
      CompletionKit::RunMetric.create!(run: run, metric: metric_a, position: 1)
      CompletionKit::RunMetric.create!(run: run, metric: metric_b, position: 2)

      r1 = run.responses.create!(status: "succeeded", response_text: "done")
      r1.reviews.create!(metric: metric_a, status: "succeeded", metric_name: metric_a.name,
                         metric_version: CompletionKit::MetricVersion.ensure_current_for(metric_a))
      r1.reviews.create!(metric: metric_b, status: "pending", metric_name: metric_b.name,
                         metric_version: CompletionKit::MetricVersion.ensure_current_for(metric_b))

      snapshot = run.progress_snapshot

      expect(snapshot[:judged_total]).to eq(1)
      expect(snapshot[:judged_done]).to eq(0)
      expect(snapshot[:judged_failed]).to eq(0)
    end

    it "counts a row as judged_failed when any of its metric reviews failed" do
      metric_a = create(:completion_kit_metric, name: "A")
      metric_b = create(:completion_kit_metric, name: "B")
      run = create(:completion_kit_run, prompt: prompt, judge_model: "gpt-4o", progress_total: 1)
      CompletionKit::RunMetric.create!(run: run, metric: metric_a, position: 1)
      CompletionKit::RunMetric.create!(run: run, metric: metric_b, position: 2)

      r1 = run.responses.create!(status: "succeeded", response_text: "done")
      r1.reviews.create!(metric: metric_a, status: "succeeded", metric_name: metric_a.name,
                         metric_version: CompletionKit::MetricVersion.ensure_current_for(metric_a))
      r1.reviews.create!(metric: metric_b, status: "failed", metric_name: metric_b.name,
                         metric_version: CompletionKit::MetricVersion.ensure_current_for(metric_b))

      snapshot = run.progress_snapshot

      expect(snapshot[:judged_total]).to eq(1)
      expect(snapshot[:judged_done]).to eq(0)
      expect(snapshot[:judged_failed]).to eq(1)
    end
  end

  describe "status enum" do
    it "rejects the legacy generating status" do
      run = build(:completion_kit_run, status: "generating")
      expect(run).not_to be_valid
    end

    it "rejects the legacy judging status" do
      run = build(:completion_kit_run, status: "judging")
      expect(run).not_to be_valid
    end

    it "accepts running" do
      run = build(:completion_kit_run, status: "running")
      expect(run).to be_valid
    end
  end

  describe ".preload_summaries" do
    let(:sum_prompt) { create(:completion_kit_prompt, template: "Static prompt") }

    it "injects response_count, avg_score, check_pass_rate, and metric_averages matching the per-run reader methods" do
      metric = create(:completion_kit_metric)
      check = create(:completion_kit_metric, :check)
      run = create(:completion_kit_run, prompt: sum_prompt, status: "completed")
      [3.0, 4.0, 5.0, 2.0].each_with_index do |score, i|
        resp = create(:completion_kit_response, run: run, status: "succeeded", row_index: i, response_text: "b#{i}")
        create(:completion_kit_review, response: resp, metric: metric, metric_name: "Quality", ai_score: score)
        create(:completion_kit_review, :check, response: resp, metric: check, metric_name: "Valid JSON", passed: i.even?)
      end
      create(:completion_kit_review, response: run.responses.order(:row_index).first,
             metric: create(:completion_kit_metric), metric_name: "Unscored",
             status: "pending", ai_score: nil, passed: nil)

      computed = CompletionKit::Run.find(run.id)
      expected = {
        count: computed.responses.size,
        avg: computed.avg_score,
        pass: computed.check_pass_rate,
        metrics: computed.metric_averages.sort_by { |m| m[:name] }
      }

      preloaded = CompletionKit::Run.preload_summaries([CompletionKit::Run.find(run.id)]).first

      expect(preloaded.response_count).to eq(expected[:count])
      expect(preloaded.avg_score).to eq(expected[:avg])
      expect(preloaded.check_pass_rate).to eq(expected[:pass])
      expect(preloaded.metric_averages.sort_by { |m| m[:name] }).to eq(expected[:metrics])
    end

    it "injects a zero count and nil aggregates for a run with responses but no reviews" do
      run = create(:completion_kit_run, prompt: sum_prompt)
      create(:completion_kit_response, run: run)
      create(:completion_kit_response, run: run)

      preloaded = CompletionKit::Run.preload_summaries([CompletionKit::Run.find(run.id)]).first

      expect(preloaded.response_count).to eq(2)
      expect(preloaded.avg_score).to be_nil
      expect(preloaded.check_pass_rate).to be_nil
      expect(preloaded.metric_averages).to eq([])
    end

    it "averages the fraction a scoring check leaves behind, on both the SQL and in-memory paths" do
      check = create(:completion_kit_metric, :check)
      run = create(:completion_kit_run, prompt: sum_prompt, status: "completed")
      [[0.5, false], [1.0, true], [0.75, false]].each_with_index do |(fraction, passed), i|
        resp = create(:completion_kit_response, run: run, status: "succeeded", row_index: i, response_text: "b#{i}")
        create(:completion_kit_review, :check, response: resp, metric: check, metric_name: "Option codes",
               passed: passed, check_score: fraction)
      end

      computed = CompletionKit::Run.find(run.id).metric_averages
      preloaded = CompletionKit::Run.preload_summaries([CompletionKit::Run.find(run.id)]).first.metric_averages

      expect(computed.first[:avg_check_score]).to eq(0.75)
      expect(computed.first[:pass_rate]).to eq(0.33)
      expect(preloaded).to eq(computed)
    end

    it "leaves avg_check_score off a check that scores nothing but pass or fail" do
      check = create(:completion_kit_metric, :check)
      run = create(:completion_kit_run, prompt: sum_prompt, status: "completed")
      resp = create(:completion_kit_response, run: run, status: "succeeded", row_index: 0, response_text: "b")
      create(:completion_kit_review, :check, response: resp, metric: check, metric_name: "Valid JSON", passed: true)

      computed = CompletionKit::Run.find(run.id).metric_averages
      preloaded = CompletionKit::Run.preload_summaries([CompletionKit::Run.find(run.id)]).first.metric_averages

      expect(computed.first).not_to have_key(:avg_check_score)
      expect(preloaded).to eq(computed)
    end

    it "returns the collection unchanged when given no runs" do
      expect(CompletionKit::Run.preload_summaries([])).to eq([])
    end
  end

  describe "#mark_completed!" do
    let(:mc_prompt) { create(:completion_kit_prompt, template: "Static prompt") }

    it "fails the run with an aggregated reason when every response failed" do
      run = create(:completion_kit_run, prompt: mc_prompt, status: "running")
      create(:completion_kit_response, run: run, status: "failed", row_index: 0, error_message: "Error: 401 Unauthorized")
      create(:completion_kit_response, run: run, status: "failed", row_index: 1)

      run.mark_completed!

      expect(run.reload.status).to eq("failed")
      expect(run.failure_summary).to include("Every response failed to generate (2 of 2)")
      expect(run.failure_summary).to include("401 Unauthorized")
    end

    it "falls back to a generic reason when the failed responses carry no error message" do
      run = create(:completion_kit_run, prompt: mc_prompt, status: "running")
      create(:completion_kit_response, run: run, status: "failed", row_index: 0)

      run.mark_completed!

      expect(run.reload.status).to eq("failed")
      expect(run.failure_summary).to include("Check the model and provider configuration")
    end

    it "completes normally when at least one response succeeded" do
      run = create(:completion_kit_run, prompt: mc_prompt, status: "running")
      create(:completion_kit_response, run: run, status: "succeeded", row_index: 0)
      create(:completion_kit_response, run: run, status: "failed", row_index: 1)

      run.mark_completed!

      expect(run.reload.status).to eq("completed")
    end
  end

  describe "a model id no configured provider serves" do
    let(:llm_metric) { create(:completion_kit_metric) }
    let(:check_metric) { create(:completion_kit_metric, :check) }

    before do
      allow(CompletionKit::ModelDiscoveryJob).to receive(:perform_later)
      allow(CompletionKit::JudgeReviewJob).to receive(:perform_later)
      allow(CompletionKit::CheckReviewJob).to receive(:perform_later)
      allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
      allow(CompletionKit::StartRunJob).to receive(:perform_later)
      create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
      create(:completion_kit_model, provider: "openai", model_id: "gpt-4.1-mini")
      create(:completion_kit_model, provider: "ollama", model_id: "llama3", status: "retired")
    end

    def run_with_judge(judge_model, metrics)
      run = create(:completion_kit_run, judge_model: "gpt-4.1-mini")
      run.update_columns(judge_model: judge_model)
      run.replace_metrics!(metrics.map(&:id))
      run
    end

    it "rejects a newly chosen judge_model on create and on update" do
      run = build(:completion_kit_run, judge_model: "llama3")
      expect(run).not_to be_valid
      expect(run.errors.full_messages).to include(%(Judge model "llama3" is not served by any configured provider))

      saved = create(:completion_kit_run, judge_model: "gpt-4.1-mini")
      expect(saved.update(judge_model: "ollama/llama3")).to be(false)
      expect(saved.errors.full_messages).to include(%(Judge model "ollama/llama3" is not served by any configured provider))
    end

    it "keeps a run editable when its judge was retired after it was saved" do
      run = run_with_judge("llama3", [llm_metric])

      expect(run.update(name: "Renamed")).to be(true)
    end

    it "refuses to rerun a run whose judge does not resolve, before creating the copy" do
      run = run_with_judge("llama3", [llm_metric])

      expect { run.rerun! }.to raise_error(CompletionKit::UnknownModelError, %(No configured provider serves judge model "llama3")) { |error|
        expect(error.model_name).to eq("llama3")
      }
      expect(described_class.count).to eq(1)
    end

    it "refuses to rerun a run whose prompt model does not resolve, before creating the copy" do
      run = create(:completion_kit_run)
      run.prompt.update_columns(llm_model: "llama3")

      expect { run.rerun! }.to raise_error(CompletionKit::UnknownModelError, %(No configured provider serves model "llama3")) { |error|
        expect(error.model_name).to eq("llama3")
      }
      expect(described_class.count).to eq(1)
    end

    it "refuses to rerun a run whose generation client is not configured, with the reason start! gives, before creating the copy" do
      unconfigured = instance_double(CompletionKit::LlmClient, configured?: false, configuration_errors: ["OpenAI API key is not configured"])
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(unconfigured)
      run = create(:completion_kit_run)

      expect { run.rerun! }.to raise_error(CompletionKit::ConfigurationError, "LLM API not configured: OpenAI API key is not configured") { |error|
        expect(error).not_to be_a(CompletionKit::UnknownModelError)
      }
      expect(described_class.count).to eq(1)

      expect(run.start!).to be(false)
      expect(run.failure_summary).to eq("LLM API not configured: OpenAI API key is not configured")
    end

    it "reruns a scoring-only run without asking for a generation client" do
      allow(CompletionKit::LlmClient).to receive(:for_model).and_call_original
      scoring = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")
      run = create(:completion_kit_run, prompt: nil, dataset: scoring)

      expect(run.rerun!).to be_persisted
      expect(CompletionKit::LlmClient).not_to have_received(:for_model)
    end

    it "reruns a check-only run whose unused judge does not resolve" do
      run = run_with_judge("llama3", [check_metric])

      expect(run.rerun!).to be_persisted
      expect(described_class.count).to eq(2)
    end

    it "fails to start, naming the model, when the prompt model does not resolve" do
      run = create(:completion_kit_run)
      run.prompt.update_columns(llm_model: "llama3")

      expect(run.start!).to be(false)
      expect(run.reload.status).to eq("failed")
      expect(run.failure_summary).to eq(%(No configured provider serves model "llama3"))
      expect(CompletionKit::StartRunJob).not_to have_received(:perform_later)
    end

    it "starts a check-only run whose unused judge does not resolve" do
      run = run_with_judge("llama3", [check_metric])

      expect(run.start!).to be(true)
      expect(run.reload.status).to eq("running")
    end

    it "reports the judge as unconfigured instead of raising" do
      run = run_with_judge("llama3", [llm_metric, check_metric])

      expect(run.judge_configured?).to be(false)
      expect(run.llm_judge_configured?).to be(false)
      expect(run.gradable?).to be(true)
    end

    it "refuses to regrade, naming the judge, instead of raising" do
      run = run_with_judge("llama3", [llm_metric])
      create(:completion_kit_response, run: run)

      expect(run.regrade!).to be(false)
      expect(run.errors.full_messages).to include(%(No configured provider serves judge model "llama3"))
      expect(run.reload.status).to eq("pending")
    end

    it "still enqueues judge reviews on regrade when the judge resolves but lacks credentials, so the run can finish" do
      allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(false)
      run = run_with_judge("gpt-4.1-mini", [llm_metric, check_metric])
      response_row = create(:completion_kit_response, run: run)

      expect(run.regrade!).to be(true)
      expect(CompletionKit::JudgeReviewJob).to have_received(:perform_later).with(response_row.id, llm_metric.id, run.id)
    end
  end
end
