require "rails_helper"

RSpec.describe "CompletionKit metrics", type: :request do
  let(:base_path) { "/completion_kit/metrics" }

  it "covers index, show, new, edit, create, update, invalid branches, and destroy" do
    metric = create(:completion_kit_metric, name: "Helpfulness")

    get base_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Helpfulness")

    get "#{base_path}/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Instruction")

    get "#{base_path}/#{metric.id}"
    expect(response).to have_http_status(:ok)

    get "#{base_path}/#{metric.id}/edit"
    expect(response).to have_http_status(:ok)

    expect do
      post base_path, params: { metric: { name: "Accuracy", instruction: "Be exact" } }
    end.to change(CompletionKit::Metric, :count).by(1)
    expect(response).to redirect_to(%r{/completion_kit/metrics/\d+})

    post base_path, params: { metric: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    patch "#{base_path}/#{metric.id}", params: { metric: { instruction: "Updated instruction" } }
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
    expect(metric.reload.instruction).to eq("Updated instruction")

    patch "#{base_path}/#{metric.id}", params: { metric: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    expect do
      delete "#{base_path}/#{metric.id}"
    end.to change(CompletionKit::Metric, :count).by(-1)

    expect(response).to redirect_to("/completion_kit/metrics")
  end

  it "round-trips tag_names on create and update" do
    post "/completion_kit/metrics", params: {
      metric: { name: "Tagged metric", instruction: "x", tag_names: ["marine biology", "factual"] }
    }
    metric = CompletionKit::Metric.find_by!(name: "Tagged metric")
    expect(metric.tag_names).to match_array(["marine biology", "factual"])

    patch "/completion_kit/metrics/#{metric.id}", params: {
      metric: { tag_names: ["marine biology"] }
    }
    expect(metric.reload.tag_names).to eq(["marine biology"])

    patch "/completion_kit/metrics/#{metric.id}", params: {
      metric: { tag_names: [""] }
    }
    expect(metric.reload.tag_names).to eq([])
  end

  it "filters metrics by tag" do
    marine_metric = create(:completion_kit_metric, name: "Shark accuracy")
    real_estate_metric = create(:completion_kit_metric, name: "Property listing tone")
    marine_metric.update!(tag_names: ["marine biology"])
    real_estate_metric.update!(tag_names: ["real estate"])

    get "/completion_kit/metrics?tag[]=marine biology"
    expect(response.body).to include("Shark accuracy")
    expect(response.body).not_to include("Property listing tone")

    get "/completion_kit/metrics?tag[]=marine biology&tag[]=real estate"
    expect(response.body).to include("Shark accuracy")
    expect(response.body).to include("Property listing tone")

    get "/completion_kit/metrics"
    expect(response.body).to include("Shark accuracy")
    expect(response.body).to include("Property listing tone")
  end

  it "renders no filter bar when no tags exist" do
    create(:completion_kit_metric, name: "Helpfulness")
    get "/completion_kit/metrics"
    expect(response.body).not_to include("Filter by tag")
  end

  it "shows the filter bar when tags exist" do
    CompletionKit::Tag.create!(name: "z")
    create(:completion_kit_metric, name: "Helpfulness")
    get "/completion_kit/metrics"
    expect(response.body).to include("Filter by tag")
  end

  it "shows each metric's published version in the index, defaulting to v1" do
    versioned = create(:completion_kit_metric, name: "Versioned metric")
    CompletionKit::MetricVersion.ensure_current_for(versioned)
    v2 = CompletionKit::MetricVersion.create!(metric: versioned, instruction: "v2 instruction", rubric_bands: versioned.rubric_bands || [], state: "draft", source: "edit")
    v2.publish!
    create(:completion_kit_metric, name: "Unversioned metric")

    get base_path

    expect(response.body).to include("ck-chip--soft")
    expect(response.body).to include("v2")
    expect(response.body).to include("v1")
  end

  it "renders the delete control as its own top-level form so it issues DELETE, not a Turbo-swallowed PATCH" do
    record = create(:completion_kit_metric)

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

  it "keeps the edit form intact (Save not orphaned, no swallowed DELETE) when a draft banner is showing" do
    metric = create(:completion_kit_metric, name: "Draft Metric")
    CompletionKit::MetricVersion.ensure_current_for(metric)
    CompletionKit::MetricVersion.create!(metric: metric, instruction: "draft instruction",
      rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")

    get "#{base_path}/#{metric.id}/edit"
    expect(response.body).to include("Discard draft")

    doc = Nokogiri::HTML5(response.body)
    target = "#{base_path}/#{metric.id}"
    edit_form = doc.css("form").find { |f| f["action"] == target && f.css("input[name='_method']").any? { |i| i["value"] == "patch" } }
    expect(edit_form).to be_present
    expect(edit_form.css("input[name='_method']").map { |i| i["value"] }).to eq(["patch"])

    save = doc.css("input[type='submit'], button[type='submit']").find { |b| (b["value"].to_s + b.text.to_s).include?("Save metric") }
    expect(save.ancestors("form").first).to eq(edit_form)
    name_field = doc.at_css("input[name='metric[name]']")
    expect(name_field.ancestors("form").first).to eq(edit_form)
  end

end
