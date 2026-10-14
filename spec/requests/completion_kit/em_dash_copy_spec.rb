require "rails_helper"

RSpec.describe "CompletionKit copy without em dashes", type: :request do
  let(:em_dash) { "\u2014" }

  it "keeps em dashes out of every engine string outside comments and lone empty-cell placeholders" do
    sources = Dir[CompletionKit::Engine.root.join("{app,lib}/**/*.{rb,erb,js,rake}").to_s]
    offenders = sources.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        next unless line.include?(em_dash)
        next if line.strip.start_with?("#", "<%#", "//", "/*", "*")

        remainder = line.gsub(/>#{em_dash}</o, "").gsub(/"#{em_dash}"/o, "")
        "#{path.delete_prefix("#{CompletionKit::Engine.root}/")}:#{index + 1}" if remainder.include?(em_dash)
      end
    end

    expect(offenders).to be_empty
  end

  it "titles each page with a middle dot before the product name" do
    get "/completion_kit/prompts/new"

    expect(Nokogiri::HTML5(response.body).at_css("title").text).to eq("New prompt · CompletionKit")
  end

  it "joins a failed row's provider error to its message with a colon" do
    run = create(:completion_kit_run)
    create(:completion_kit_response, :failed, run: run, error_provider: "openai", error_status: 429, error_message: "Rate limit exceeded")

    get "/completion_kit/runs/#{run.id}"

    expect(Nokogiri::HTML5(response.body).at_css(".ck-response-cell__error").text).to eq("Openai 429: Rate limit exceeded")
  end

  it "offers sample data in plain sentences" do
    get "/completion_kit/onboarding"

    copy = Nokogiri::HTML5(response.body).at_css(".ck-launch__sample-copy").text
    expect(copy).to eq("Just exploring? Drop in a sample dataset and prompt to poke around. They're labelled Sample:, and you can edit or delete them whenever.")
  end

  it "tells a scoring-only run whose dataset lacks the output column what to do in two sentences" do
    get "/completion_kit/runs/new"

    script = Nokogiri::HTML5(response.body).css("form script").map(&:text).join
    expect(script).to include(%q{"Dataset has no \"" + col + "\" column. Pick a different output column or dataset."})
  end
end
