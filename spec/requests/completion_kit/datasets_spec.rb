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
    expect(response.body).to include("Download CSV")
  end

  it "downloads the dataset as a CSV attachment named from the dataset" do
    csv = "ticket,priority\nA broken switch,P2\n"
    dataset = create(:completion_kit_dataset, name: "Customer Tickets — sample", csv_data: csv)

    get "#{base_path}/#{dataset.id}.csv"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/csv")
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(response.headers["Content-Disposition"]).to include("customer-tickets-sample.csv")
    expect(response.body).to eq(csv)
  end

  it "falls back to a dataset-id filename when the name slugifies to blank" do
    dataset = create(:completion_kit_dataset, name: "—", csv_data: "a,b\n1,2\n")

    get "#{base_path}/#{dataset.id}.csv"

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include("dataset-#{dataset.id}.csv")
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

  it "round-trips tag_names on create and update" do
    post "/completion_kit/datasets", params: {
      dataset: { name: "D", csv_data: "input\nhello", tag_names: ["gamma"] }
    }
    dataset = CompletionKit::Dataset.find_by!(name: "D")
    expect(dataset.tag_names).to eq(["gamma"])

    patch "/completion_kit/datasets/#{dataset.id}", params: {
      dataset: { tag_names: [] }
    }
    expect(dataset.reload.tag_names).to eq([])
  end

  it "filters datasets by tag" do
    marine_dataset = create(:completion_kit_dataset, name: "Shark sightings")
    real_estate_dataset = create(:completion_kit_dataset, name: "Property listings")
    marine_dataset.update!(tag_names: ["marine biology"])
    real_estate_dataset.update!(tag_names: ["real estate"])

    get "/completion_kit/datasets?tag[]=marine biology"
    expect(response.body).to include("Shark sightings")
    expect(response.body).not_to include("Property listings")

    get "/completion_kit/datasets?tag[]=marine biology&tag[]=real estate"
    expect(response.body).to include("Shark sightings")
    expect(response.body).to include("Property listings")

    get "/completion_kit/datasets"
    expect(response.body).to include("Shark sightings")
    expect(response.body).to include("Property listings")
  end

  it "renders no filter bar when no tags exist" do
    create(:completion_kit_dataset, name: "Support Tickets")
    get "/completion_kit/datasets"
    expect(response.body).not_to include("Filter by tag")
  end

  it "shows the filter bar when tags exist" do
    CompletionKit::Tag.create!(name: "z")
    create(:completion_kit_dataset, name: "Support Tickets")
    get "/completion_kit/datasets"
    expect(response.body).to include("Filter by tag")
  end

end
