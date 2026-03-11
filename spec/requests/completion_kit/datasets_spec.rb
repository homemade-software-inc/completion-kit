require "rails_helper"

RSpec.describe "CompletionKit datasets", type: :request do
  let(:base_path) { "/completion_kit/datasets" }
  let(:valid_csv) do
    <<~CSV
      content,audience,expected_output
      "Release notes","developers","A developer-focused summary"
    CSV
  end

  it "renders index with datasets table" do
    dataset = create(:completion_kit_dataset, name: "Support Tickets")

    get base_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Support Tickets")
  end

  it "renders show with CSV preview and runs table" do
    dataset = create(:completion_kit_dataset, name: "Visible Dataset")
    run = create(:completion_kit_run, dataset: dataset, name: "Run on dataset")

    get "#{base_path}/#{dataset.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visible Dataset")
    expect(response.body).to include("CSV preview")
    expect(response.body).to include("Run on dataset")
  end

  it "renders the new form" do
    get "#{base_path}/new"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("New dataset")
  end

  it "creates a dataset with valid params" do
    expect do
      post base_path, params: { dataset: { name: "New Dataset", csv_data: valid_csv } }
    end.to change(CompletionKit::Dataset, :count).by(1)

    expect(response).to redirect_to("/completion_kit/datasets")
  end

  it "renders new when create is invalid" do
    post base_path, params: { dataset: { name: "", csv_data: valid_csv } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("prevented this dataset from being saved")
  end

  it "updates a dataset with valid params" do
    dataset = create(:completion_kit_dataset, name: "Old Name")

    patch "#{base_path}/#{dataset.id}", params: { dataset: { name: "New Name" } }

    expect(response).to redirect_to("/completion_kit/datasets/#{dataset.id}")
    expect(dataset.reload.name).to eq("New Name")
  end

  it "renders edit when update is invalid" do
    dataset = create(:completion_kit_dataset, name: "Old Name")

    patch "#{base_path}/#{dataset.id}", params: { dataset: { name: "" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("prevented this dataset from being saved")
  end

  it "destroys a dataset" do
    dataset = create(:completion_kit_dataset)

    expect do
      delete "#{base_path}/#{dataset.id}"
    end.to change(CompletionKit::Dataset, :count).by(-1)

    expect(response).to redirect_to("/completion_kit/datasets")
  end
end
