require "rails_helper"

# Regression: the engine's lazy route set materialises non-atomically on
# first access. Worker threads rendering engine partials for Turbo broadcasts
# raced that first load and raised "undefined method 'run_response_path'".
# `warm_routes!` materialises it once, single-threaded, ahead of the renders.
RSpec.describe "CompletionKit::Engine.warm_routes!" do
  it "materialises the engine route helpers and is idempotent" do
    CompletionKit::Engine.instance_variable_set(:@routes_warmed, false)

    expect { CompletionKit::Engine.warm_routes! }.not_to raise_error
    expect(CompletionKit::Engine.instance_variable_get(:@routes_warmed)).to be(true)

    # A second call is a no-op early return — still safe, still idempotent.
    expect { CompletionKit::Engine.warm_routes! }.not_to raise_error
    expect(CompletionKit::Engine.routes.url_helpers.run_response_path(1, 2))
      .to eq("/completion_kit/runs/1/responses/2")
  end

  it "is safe to call concurrently from many threads" do
    CompletionKit::Engine.instance_variable_set(:@routes_warmed, false)

    results = []
    mutex = Mutex.new
    threads = 12.times.map do
      Thread.new do
        outcome = begin
          CompletionKit::Engine.warm_routes!
          :ok
        rescue => e
          e.class
        end
        mutex.synchronize { results << outcome }
      end
    end
    threads.each(&:join)

    expect(results).to all(eq(:ok))
  end

  it "still warms (and does not raise) when a parameterized mount makes the bare helper raise" do
    CompletionKit::Engine.instance_variable_set(:@routes_warmed, false)
    helpers = CompletionKit::Engine.routes.url_helpers
    allow(helpers).to receive(:root_path)
      .and_raise(ActionController::UrlGenerationError.new("missing required keys: [:org_slug]"))
    allow(CompletionKit::Engine.routes).to receive(:url_helpers).and_return(helpers)

    expect { CompletionKit::Engine.warm_routes! }.not_to raise_error
    expect(CompletionKit::Engine.instance_variable_get(:@routes_warmed)).to be(true)
  ensure
    CompletionKit::Engine.instance_variable_set(:@routes_warmed, true)
  end
end
