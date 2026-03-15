# REST JSON API Design

**Goal:** Replace the eval DSL with a REST JSON API so tools like Claude Code can CRUD all resources and trigger generation/judging programmatically.

**Two workstreams:**
1. Add REST API endpoints with bearer token auth
2. Remove the eval DSL

---

## Part 1: API Authentication

### Configuration

New `api_token` attribute on `CompletionKit::Configuration`:

```ruby
CompletionKit.configure do |c|
  c.api_token = Rails.application.credentials.completion_kit_api_token
end
```

### Behavior

- Token sent via `Authorization: Bearer <token>` header.
- Compared with `ActiveSupport::SecurityUtils.secure_compare`.
- No token configured → `401` with `{"error": "API token not configured"}` in all environments. No open-access mode.
- Wrong/missing token → `401` with `{"error": "Unauthorized"}`.
- API auth is completely separate from web UI auth — different controller hierarchy, different config attribute.

### Implementation

- Add `api_token` to `CompletionKit::Configuration`
- `CompletionKit::Api::V1::BaseController` inherits from `ActionController::API` (not `ActionController::Base` — no sessions, cookies, CSRF)
- `before_action :authenticate_api!` on `BaseController`
- `authenticate_api!` reads `Authorization` header, extracts bearer token, compares with `CompletionKit.config.api_token`

---

## Part 2: Routing & Namespace

All API routes nested under the existing engine mount at `/api/v1/`. If the engine is mounted at `/completion_kit`, the full paths are `/completion_kit/api/v1/...`. Paths below are relative to the engine mount.

Controllers namespaced as `CompletionKit::Api::V1::`. All collection endpoints return records ordered by `created_at: :desc`.

### Routes

```
GET/POST         /api/v1/prompts
GET/PATCH/DELETE /api/v1/prompts/:id
POST             /api/v1/prompts/:id/publish
POST             /api/v1/prompts/:id/new_version

GET/POST         /api/v1/runs
GET/PATCH/DELETE /api/v1/runs/:id
POST             /api/v1/runs/:id/generate
POST             /api/v1/runs/:id/judge
GET              /api/v1/runs/:run_id/responses
GET              /api/v1/runs/:run_id/responses/:id

GET/POST         /api/v1/datasets
GET/PATCH/DELETE /api/v1/datasets/:id

GET/POST         /api/v1/metrics
GET/PATCH/DELETE /api/v1/metrics/:id

GET/POST         /api/v1/criteria
GET/PATCH/DELETE /api/v1/criteria/:id

GET/POST         /api/v1/provider_credentials
GET/PATCH/DELETE /api/v1/provider_credentials/:id
```

### Route Definition

```ruby
namespace :api do
  namespace :v1 do
    resources :prompts do
      member do
        post :publish
        post :new_version
      end
    end

    resources :runs do
      member do
        post :generate
        post :judge
      end
      resources :responses, only: [:index, :show]
    end

    resources :datasets
    resources :metrics
    resources :criteria, controller: "criteria"
    resources :provider_credentials
  end
end
```

---

## Part 3: Response Format

Flat JSON, no root wrapping.

### Single Resource

```json
{"id": 1, "name": "summarizer", "template": "Summarize: {{text}}", "version_number": 1, "current": true, "created_at": "2026-03-14T12:00:00Z"}
```

### Collection

```json
[{"id": 1, "name": "summarizer"}, {"id": 2, "name": "classifier"}]
```

### Process Actions (generate/judge)

Run synchronously, return the updated run:

```json
{"id": 5, "status": "completed", "responses_count": 10, "avg_score": 4.2}
```

### Errors

Validation errors:
```json
{"errors": {"name": ["can't be blank"], "template": ["can't be blank"]}}
```

Not found / auth errors:
```json
{"error": "Record not found"}
{"error": "Unauthorized"}
```

### HTTP Status Codes

- `200` — success (show, update, process actions)
- `201` — created
- `204` — deleted (no body)
- `401` — unauthorized
- `404` — not found
- `422` — validation failed

---

## Part 4: Controller Structure

### BaseController

```ruby
module CompletionKit
  module Api
    module V1
      class BaseController < ActionController::API
        before_action :authenticate_api!

        private

        def authenticate_api!
          token = CompletionKit.config.api_token
          unless token
            render json: {error: "API token not configured"}, status: :unauthorized
            return
          end

          provided = request.headers["Authorization"]&.delete_prefix("Bearer ")
          unless provided && ActiveSupport::SecurityUtils.secure_compare(provided, token)
            render json: {error: "Unauthorized"}, status: :unauthorized
          end
        end

        def not_found
          render json: {error: "Record not found"}, status: :not_found
        end
      end
    end
  end
end
```

### Resource Controllers

Each follows the same pattern — standard CRUD with strong params. Example for prompts:

```ruby
module CompletionKit
  module Api
    module V1
      class PromptsController < BaseController
        before_action :set_prompt, only: [:show, :update, :destroy, :publish, :new_version]

        def index
          render json: Prompt.order(created_at: :desc)
        end

        def show
          render json: @prompt
        end

        def create
          prompt = Prompt.new(prompt_params)
          if prompt.save
            render json: prompt, status: :created
          else
            render json: {errors: prompt.errors}, status: :unprocessable_entity
          end
        end

        def update
          if @prompt.update(prompt_params)
            render json: @prompt
          else
            render json: {errors: @prompt.errors}, status: :unprocessable_entity
          end
        end

        def destroy
          @prompt.destroy!
          head :no_content
        end

        def publish
          @prompt.publish!
          render json: @prompt.reload
        end

        def new_version
          version = @prompt.clone_as_new_version
          render json: version, status: :created
        end

        private

        def set_prompt
          @prompt = Prompt.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def prompt_params
          params.permit(:name, :description, :template, :llm_model)
        end
      end
    end
  end
end
```

### Runs Controller — Process Actions

`generate` and `judge` are synchronous. The model methods rescue errors internally and set status to `"failed"`, returning `false`. The controller checks the return value:

```ruby
def generate
  if @run.generate_responses!
    render json: @run.reload
  else
    render json: {error: "Generation failed", status: @run.reload.status}, status: :unprocessable_entity
  end
end

def judge
  if @run.judge_responses!
    render json: @run.reload
  else
    render json: {error: "Judging failed", status: @run.reload.status}, status: :unprocessable_entity
  end
end
```

### Runs Controller — Nested Responses

Responses are accessible as a nested read-only resource under runs:

```
GET /api/v1/runs/:run_id/responses
GET /api/v1/runs/:run_id/responses/:id
```

The responses index returns all responses for a run with their reviews included. The show action returns a single response with reviews.

### Strong Params for All Controllers

- **Runs:** `:name, :prompt_id, :dataset_id, :judge_model, :criteria_id`
- **Datasets:** `:name, :csv_data`
- **Metrics:** `:name, :criteria, evaluation_steps: [], rubric_bands: [:stars, :description]`
- **Criteria:** `:name, :description, metric_ids: []`
- **Provider Credentials:** `:provider, :api_key, :api_endpoint`

---

## Part 5: JSON Serialization

Use `as_json` overrides on each model to control which attributes are exposed. No external serializer gem.

### Attributes per Model

- **Prompt:** `id, name, description, template, llm_model, family_key, version_number, current, created_at, updated_at`
- **Run:** `id, name, status, prompt_id, dataset_id, criteria_id, judge_model, created_at, updated_at` + computed: `responses_count` (via `responses.count`), `avg_score` (via existing method)
- **Dataset:** `id, name, csv_data, created_at, updated_at`
- **Metric:** `id, name, key, criteria, evaluation_steps, rubric_bands, created_at, updated_at`
- **Criteria:** `id, name, description, created_at, updated_at` + `metric_ids` array
- **ProviderCredential:** `id, provider, api_endpoint, created_at, updated_at` — **excludes `api_key`** (never expose secrets via API; API key is write-only)
- **Response:** `id, run_id, input_data, response_text, expected_output, created_at` + computed: `score` (via existing method), `reviewed` (via existing method) + nested: `reviews` array
- **Review:** `id, response_id, metric_id, metric_name, ai_score, ai_feedback, status`

---

## Part 6: DSL Removal

### Files to Delete

- `lib/completion_kit/eval_definition.rb`
- `lib/completion_kit/eval_runner.rb`
- `lib/completion_kit/eval_formatter.rb`
- `lib/tasks/completion_kit_tasks.rake`
- `spec/services/completion_kit/eval_definition_spec.rb`
- `spec/services/completion_kit/eval_runner_spec.rb`
- `spec/services/completion_kit/eval_formatter_spec.rb`
- `spec/services/completion_kit/eval_registry_spec.rb`
- `spec/services/completion_kit/eval_integration_spec.rb`
- `spec/lib/tasks/eval_rake_spec.rb`
- `docs/eval-dsl.md`
- `docs/plans/2026-03-09-eval-dsl-implementation.md`
- `docs/plans/2026-03-09-eval-dsl-design.md`

### Code to Remove from Existing Files

**`lib/completion_kit.rb`:**
- Remove requires: `eval_definition`, `eval_runner`, `eval_formatter`
- Remove methods: `registered_evals`, `define_eval`, `clear_evals!`

**`lib/generators/completion_kit/install_generator.rb`:**
- Remove `create_eval_directory` method that scaffolds example evals

### What Stays

- `CompletionKit.current_prompt`, `current_prompt_payload`, `render_current_prompt` — useful public API independent of the DSL
- All models, services, and HTML controllers — unchanged

---

## Part 7: Documentation

### README Updates

- Remove eval DSL section
- Add API section covering:
  - Configuration (api_token)
  - Authentication (Bearer token)
  - Endpoint reference table
  - Example requests/responses for key operations (create prompt, generate, judge)

---

## File Structure

### New Files

```
app/controllers/completion_kit/api/v1/base_controller.rb
app/controllers/completion_kit/api/v1/prompts_controller.rb
app/controllers/completion_kit/api/v1/runs_controller.rb
app/controllers/completion_kit/api/v1/datasets_controller.rb
app/controllers/completion_kit/api/v1/metrics_controller.rb
app/controllers/completion_kit/api/v1/criteria_controller.rb
app/controllers/completion_kit/api/v1/provider_credentials_controller.rb
app/controllers/completion_kit/api/v1/responses_controller.rb
```

### Modified Files

```
lib/completion_kit.rb                                    — add api_token, remove DSL
lib/generators/completion_kit/install_generator.rb       — remove eval scaffolding, add api_token to template
lib/generators/completion_kit/templates/initializer.rb   — add commented api_token line
config/routes.rb                                         — add api/v1 namespace
README.md                                                — replace eval docs with API docs
```

### Deleted Files

(See Part 6 above)

---

## Out of Scope

- Background job processing (generation/judging remain synchronous)
- Pagination
- Rate limiting
- API versioning beyond v1 (structure supports it, but only v1 built now)
- MCP server (separate future project, will call this API)
