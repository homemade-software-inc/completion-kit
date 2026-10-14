require "rails_helper"

RSpec.describe "CompletionKit metric groups", type: :request do
  let(:base_path) { "/completion_kit/metric_groups" }

  it "covers index, show, new, edit, create, update, invalid branches, and destroy" do
    metric = create(:completion_kit_metric, name: "Helpfulness")
    metric_group = create(:completion_kit_metric_group)

    get base_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(metric_group.name)

    get "#{base_path}/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pick the metrics to include")

    get "#{base_path}/#{metric_group.id}"
    expect(response).to have_http_status(:ok)

    get "#{base_path}/#{metric_group.id}/edit"
    expect(response).to have_http_status(:ok)

    expect do
      post base_path, params: { metric_group: { name: "QA pack", description: "Scoring pack", metric_ids: [metric.id] } }
    end.to change(CompletionKit::MetricGroup, :count).by(1)
    expect(response).to redirect_to(%r{/completion_kit/metric_groups/\d+})
    expect(CompletionKit::MetricGroup.order(:id).last.metrics).to eq([metric])

    post base_path, params: { metric_group: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    patch "#{base_path}/#{metric_group.id}", params: { metric_group: { description: "Updated", metric_ids: [metric.id] } }
    expect(response).to redirect_to("/completion_kit/metric_groups/#{metric_group.id}")
    expect(metric_group.reload.description).to eq("Updated")
    expect(metric_group.metrics).to eq([metric])

    patch "#{base_path}/#{metric_group.id}", params: { metric_group: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    expect do
      delete "#{base_path}/#{metric_group.id}"
    end.to change(CompletionKit::MetricGroup, :count).by(-1)

    expect(response).to redirect_to("/completion_kit/metric_groups")
  end

  describe "metric choices on a failed save" do
    let!(:saved_metric) { create(:completion_kit_metric, name: "Saved") }
    let!(:chosen_metric) { create(:completion_kit_metric, name: "Chosen") }

    def ticked_metric_ids
      Nokogiri::HTML5(response.body).css("input[type='checkbox'][name='metric_group[metric_ids][]'][checked]").map { |box| box["value"].to_i }
    end

    it "keeps the chosen metrics ticked when create fails" do
      post base_path, params: { metric_group: { name: "", metric_ids: ["", chosen_metric.id] } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ticked_metric_ids).to eq([chosen_metric.id])
    end

    it "keeps the chosen metrics ticked when an update fails" do
      group = create(:completion_kit_metric_group)
      group.replace_metrics!([saved_metric.id])

      patch "#{base_path}/#{group.id}", params: { metric_group: { name: "", metric_ids: ["", chosen_metric.id] } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ticked_metric_ids).to eq([chosen_metric.id])
      expect(group.reload.metric_ids).to eq([saved_metric.id])
    end
  end

  describe "the error summary on a failed save" do
    def summary
      Nokogiri::HTML5(response.body).at_css("form .ck-flash--alert[role='alert']")
    end

    it "lists every problem above the metric list when create fails" do
      create(:completion_kit_metric, name: "Helpfulness")

      post base_path, params: { metric_group: { name: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(summary.at_css(".ck-flash__title").text).to eq("1 problem prevented this metric group from being saved.")
      expect(summary.css(".ck-error-list li").map(&:text)).to eq(["Name can't be blank"])
      expect(response.body.index("ck-flash--alert")).to be < response.body.index("data-metric-checkboxes")
    end

    it "lists the problem when an update fails" do
      group = create(:completion_kit_metric_group)

      patch "#{base_path}/#{group.id}", params: { metric_group: { name: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(summary.css(".ck-error-list li").map(&:text)).to eq(["Name can't be blank"])
    end

    it "keeps the saved name in the breadcrumb when an update blanks it" do
      group = create(:completion_kit_metric_group, name: "Support pack")

      patch "#{base_path}/#{group.id}", params: { metric_group: { name: "" } }

      crumbs = Nokogiri::HTML5(response.body).css(".ck-breadcrumb li").map { |li| li.text.strip }
      expect(crumbs).to eq(["Metrics", "Support pack", "Edit"])
    end

    it "shows no summary on a fresh form" do
      get "#{base_path}/new"

      expect(summary).to be_nil
    end
  end

  describe "with metrics from another tenant" do
    let(:own_metric) { create(:completion_kit_metric, name: "Own") }
    let!(:foreign_metric) { create(:completion_kit_metric, name: "Foreign") }

    before { hide_outside_tenant(foreign_metric) }

    it "refuses to create a group on another tenant's metric and writes nothing" do
      expect do
        post base_path, params: { metric_group: { name: "Cross", metric_ids: [own_metric.id, foreign_metric.id] } }
      end.not_to change { [CompletionKit::MetricGroup.unscoped.count, CompletionKit::MetricGroupMembership.unscoped.count] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Nokogiri::HTML5(response.body).at_css("#metric_group_metric_ids_error").text).to eq("Metrics include one that isn't available")
    end

    it "refuses to swap a group's metrics for another tenant's and keeps the old ones" do
      group = create(:completion_kit_metric_group)
      group.replace_metrics!([own_metric.id])

      patch "#{base_path}/#{group.id}", params: { metric_group: { name: group.name, metric_ids: [foreign_metric.id] } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Nokogiri::HTML5(response.body).text).to include("Metrics include one that isn't available")
      expect(group.metric_group_memberships.pluck(:metric_id)).to eq([own_metric.id])
    end
  end

  it "renders the delete control as its own top-level form so it issues DELETE, not a Turbo-swallowed PATCH" do
    record = create(:completion_kit_metric_group)

    get "#{base_path}/#{record.id}/edit"

    doc = Nokogiri::HTML5(response.body)
    target = "#{base_path}/#{record.id}"
    forms = doc.css("form").select { |f| f["action"] == target }
    patch_form = forms.find { |f| f.css("input[name='_method']").any? { |i| i["value"] == "patch" } }
    delete_form = forms.find { |f| f.css("input[name='_method']").any? { |i| i["value"] == "delete" } }

    expect(patch_form).to be_present
    expect(delete_form).to be_present
    expect(patch_form).not_to eq(delete_form)

    expect(delete_form["id"]).to be_present
    trigger = doc.at_css("button[type='submit'][form='#{delete_form["id"]}']")
    expect(trigger).to be_present
    expect(trigger["data-turbo-confirm"]).to be_present
  end
end
