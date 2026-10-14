require "rails_helper"

RSpec.describe CompletionKit::Configuration do
  it "defaults the run-display seams to nil and no longer exposes the 0.16.3 names" do
    config = described_class.new
    expect(config.runs_display_scope).to be_nil
    expect(config.runs_display_footer_partial).to be_nil
    expect(config).not_to respond_to(:runs_index_scope)
    expect(config).not_to respond_to(:runs_index_footer_partial)
  end

  it "gives each regex check pattern a one second match timeout by default" do
    expect(described_class.new.regex_timeout).to eq(1.0)
  end

  it "caps a prompt template at 1 MB by default" do
    expect(described_class.new.max_template_bytes).to eq(1024 * 1024)
  end

  it "takes a finite number of seconds from 0.001 up, or nil, for regex_timeout" do
    config = described_class.new

    [2, 0.25, Rational(1, 2), 0.001, 86_400, nil].each do |seconds|
      config.regex_timeout = seconds
      expect(config.regex_timeout).to eq(seconds)
    end
  end

  it "refuses a regex_timeout Ruby cannot use, so a bad value fails at boot instead of on every regex check" do
    config = described_class.new

    [0, -1, Float::NAN, Float::INFINITY, -Float::INFINITY, 1e-12, 0.0009, Complex(1, 0), "1", true].each do |seconds|
      expect { config.regex_timeout = seconds }
        .to raise_error(ArgumentError, "regex_timeout must be a finite number of seconds of at least 0.001, or nil, got #{seconds.inspect}")
    end
    expect(config.regex_timeout).to eq(1.0)
  end

  it "sets its smallest regex_timeout above the point where Ruby silently drops a timeout" do
    expect(Regexp.new("a", timeout: 1e-12).timeout).to be_nil
    expect(Regexp.new("a", timeout: described_class::MIN_REGEX_TIMEOUT).timeout).to eq(described_class::MIN_REGEX_TIMEOUT)
  end
end
