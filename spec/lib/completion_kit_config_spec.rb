require "rails_helper"

RSpec.describe CompletionKit::Configuration do
  it "defaults the run-display seams to nil and no longer exposes the 0.16.3 names" do
    config = described_class.new
    expect(config.runs_display_scope).to be_nil
    expect(config.runs_display_footer_partial).to be_nil
    expect(config).not_to respond_to(:runs_index_scope)
    expect(config).not_to respond_to(:runs_index_footer_partial)
  end
end
