# Rename Criteria → MetricGroup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the `Criteria` concept to `MetricGroup` across database, Ruby classes, URLs, REST API, MCP tools, views, tests, seeds, and docs. No backwards-compatibility aliases.

**Architecture:** Mechanical rename. Tests will NOT pass at intermediate steps — rename every layer, then run the suite once at the end, then commit once, then push once. A single reversible migration handles the schema. The engine migration is copied into `standalone/db/migrate/` so Render's pre-deploy runs it against Supabase.

**Tech Stack:** Rails 8.1 engine, RSpec + FactoryBot, PostgreSQL (Supabase prod, SQLite in-memory test), Render + Supabase for prod.

**Spec:** `docs/superpowers/specs/2026-04-17-rename-criteria-to-metric-groups-design.md`

---

## Ground rules

- **One commit for the whole rename.** Do not commit between tasks; the suite is red until every layer is renamed. One final commit + push after the suite is green.
- **Delete, don't copy.** File moves use `git mv` so the rename shows cleanly in history.
- **No aliases.** No `Criteria = MetricGroup` constant, no URL redirects, no MCP tool aliases. Clean break.
- **Text updates matter.** "A criteria groups metrics" → "A metric group groups metrics for reuse" style; adjust English grammar (criteria plural → metric groups plural).

---

## Task 1: Engine migration

**Files:**
- Create: `db/migrate/20260417000001_rename_criteria_to_metric_groups.rb`

- [ ] **Step 1: Write the migration**

```ruby
class RenameCriteriaToMetricGroups < ActiveRecord::Migration[8.1]
  def change
    rename_table :completion_kit_criteria, :completion_kit_metric_groups
    rename_table :completion_kit_criteria_memberships, :completion_kit_metric_group_memberships
    rename_column :completion_kit_metric_group_memberships, :criteria_id, :metric_group_id
  end
end
```

No commit. Move to Task 2.

---

## Task 2: Rename model files

**Files:**
- Move: `app/models/completion_kit/criteria.rb` → `app/models/completion_kit/metric_group.rb`
- Move: `app/models/completion_kit/criteria_membership.rb` → `app/models/completion_kit/metric_group_membership.rb`

- [ ] **Step 1: `git mv` both files**

```bash
git mv app/models/completion_kit/criteria.rb app/models/completion_kit/metric_group.rb
git mv app/models/completion_kit/criteria_membership.rb app/models/completion_kit/metric_group_membership.rb
```

- [ ] **Step 2: Rewrite `app/models/completion_kit/metric_group.rb`**

```ruby
module CompletionKit
  class MetricGroup < ApplicationRecord
    self.table_name = "completion_kit_metric_groups"

    has_many :metric_group_memberships, -> { order(:position, :id) }, dependent: :destroy
    has_many :metrics, through: :metric_group_memberships

    validates :name, presence: true

    def ordered_metrics
      metric_group_memberships.includes(:metric).map(&:metric).compact
    end

    def as_json(options = {})
      {
        id: id, name: name, description: description,
        created_at: created_at, updated_at: updated_at,
        metric_ids: metric_ids
      }
    end
  end
end
```

- [ ] **Step 3: Rewrite `app/models/completion_kit/metric_group_membership.rb`**

```ruby
module CompletionKit
  class MetricGroupMembership < ApplicationRecord
    self.table_name = "completion_kit_metric_group_memberships"

    belongs_to :metric_group, class_name: "CompletionKit::MetricGroup", foreign_key: "metric_group_id"
    belongs_to :metric

    validates :metric_id, uniqueness: { scope: :metric_group_id }

    before_validation :set_default_position

    private

    def set_default_position
      return if position.present? || metric_group.blank?

      self.position = metric_group.metric_group_memberships.maximum(:position).to_i + 1
    end
  end
end
```

---

## Task 3: Update `Metric` associations

**Files:**
- Modify: `app/models/completion_kit/metric.rb:11-12`

- [ ] **Step 1: Replace the two association lines**

```ruby
has_many :metric_group_memberships, dependent: :destroy
has_many :metric_groups, through: :metric_group_memberships, source: :metric_group
```

(Old lines referenced `criteria_memberships` and `criterias`. Both go.)

---

## Task 4: Remove the inflection rule

**Files:**
- Modify: `lib/completion_kit/engine.rb:8-12`

- [ ] **Step 1: Delete the initializer block**

Remove these lines entirely from `lib/completion_kit/engine.rb`:

```ruby
initializer("completion_kit.inflections", before: :load_config_initializers) do
  ActiveSupport::Inflector.inflections(:en) do |inflect|
    inflect.irregular "criterion", "criteria"
  end
end
```

The `MetricGroup` class name pluralizes naturally. No custom inflection needed.

---

## Task 5: Rename web controller

**Files:**
- Move: `app/controllers/completion_kit/criteria_controller.rb` → `app/controllers/completion_kit/metric_groups_controller.rb`

- [ ] **Step 1: `git mv`**

```bash
git mv app/controllers/completion_kit/criteria_controller.rb app/controllers/completion_kit/metric_groups_controller.rb
```

- [ ] **Step 2: Rewrite the file**

```ruby
module CompletionKit
  class MetricGroupsController < ApplicationController
    before_action :set_metric_group, only: [:show, :edit, :update, :destroy]

    def index
      @metric_groups = MetricGroup.includes(:metrics).order(:name)
    end

    def show
    end

    def new
      @metric_group = MetricGroup.new
      @metrics = Metric.order(:name)
    end

    def edit
      @metrics = Metric.order(:name)
    end

    def create
      @metric_group = MetricGroup.new(metric_group_params.except(:metric_ids))
      @metrics = Metric.order(:name)

      if @metric_group.save
        replace_metric_memberships
        redirect_to metric_group_path(@metric_group), notice: "Metric group was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @metrics = Metric.order(:name)

      if @metric_group.update(metric_group_params.except(:metric_ids))
        replace_metric_memberships
        redirect_to metric_group_path(@metric_group), notice: "Metric group was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @metric_group.destroy
      redirect_to metric_groups_path, notice: "Metric group was successfully destroyed."
    end

    private

    def set_metric_group
      @metric_group = MetricGroup.find(params[:id])
    end

    def metric_group_params
      params.require(:metric_group).permit(:name, :description, metric_ids: [])
    end

    def replace_metric_memberships
      metric_ids = Array(metric_group_params[:metric_ids]).reject(&:blank?)
      @metric_group.metric_group_memberships.delete_all
      metric_ids.each_with_index do |metric_id, index|
        @metric_group.metric_group_memberships.create!(metric_id: metric_id, position: index + 1)
      end
    end
  end
end
```

---

## Task 6: Rename API controller

**Files:**
- Move: `app/controllers/completion_kit/api/v1/criteria_controller.rb` → `app/controllers/completion_kit/api/v1/metric_groups_controller.rb`

- [ ] **Step 1: `git mv`**

```bash
git mv app/controllers/completion_kit/api/v1/criteria_controller.rb app/controllers/completion_kit/api/v1/metric_groups_controller.rb
```

- [ ] **Step 2: Rewrite the file**

```ruby
module CompletionKit
  module Api
    module V1
      class MetricGroupsController < BaseController
        before_action :set_metric_group, only: [:show, :update, :destroy]

        def index
          render json: MetricGroup.order(created_at: :desc)
        end

        def show
          render json: @metric_group
        end

        def create
          metric_group = MetricGroup.new(metric_group_params.except(:metric_ids))
          if metric_group.save
            replace_metric_memberships(metric_group, params[:metric_ids]) if params.key?(:metric_ids)
            render json: metric_group.reload, status: :created
          else
            render json: {errors: metric_group.errors}, status: :unprocessable_entity
          end
        end

        def update
          if @metric_group.update(metric_group_params.except(:metric_ids))
            replace_metric_memberships(@metric_group, params[:metric_ids]) if params.key?(:metric_ids)
            render json: @metric_group.reload
          else
            render json: {errors: @metric_group.errors}, status: :unprocessable_entity
          end
        end

        def destroy
          @metric_group.destroy!
          head :no_content
        end

        private

        def set_metric_group
          @metric_group = MetricGroup.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def metric_group_params
          params.permit(:name, :description, metric_ids: [])
        end

        def replace_metric_memberships(metric_group, metric_ids)
          return unless metric_ids

          metric_group.metric_group_memberships.delete_all
          Array(metric_ids).reject(&:blank?).each_with_index do |metric_id, index|
            metric_group.metric_group_memberships.create!(metric_id: metric_id, position: index + 1)
          end
        end
      end
    end
  end
end
```

---

## Task 7: Update routes

**Files:**
- Modify: `config/routes.rb:12` and `config/routes.rb:48`

- [ ] **Step 1: Replace both `resources :criteria, controller: "criteria"` lines**

Line 12 (web):
```ruby
resources :metric_groups
```

Line 48 (API, inside `namespace :api do; namespace :v1 do`):
```ruby
resources :metric_groups
```

(No `controller:` option needed — standard Rails convention pairs `resources :metric_groups` with `MetricGroupsController`.)

---

## Task 8: Rename views directory + rewrite view files

**Files:**
- Move: `app/views/completion_kit/criteria/` → `app/views/completion_kit/metric_groups/`

- [ ] **Step 1: `git mv` the directory**

```bash
git mv app/views/completion_kit/criteria app/views/completion_kit/metric_groups
```

- [ ] **Step 2: Rewrite `app/views/completion_kit/metric_groups/index.html.erb`**

```erb
<ol class="ck-breadcrumb">
  <li><%= link_to "Metrics", metrics_path %></li>
  <li>Metric groups</li>
</ol>

<section class="ck-page-header">
  <div>
    <h1 class="ck-title">Metric groups</h1>
    <p class="ck-lead">Named groups of metrics. Apply a group to a run to score outputs against every metric in the group at once.</p>
  </div>
  <div class="ck-actions">
    <%= link_to "New metric group", new_metric_group_path, class: ck_button_classes(:dark) %>
  </div>
</section>

<% if @metric_groups.any? %>
  <table class="ck-results-table">
    <thead>
      <tr>
        <th>Name</th>
        <th>Description</th>
        <th>Metrics</th>
        <th></th>
      </tr>
    </thead>
    <tbody>
      <% @metric_groups.each do |metric_group| %>
        <tr onclick="window.location='<%= metric_group_path(metric_group) %>'" style="cursor: pointer;">
          <td><strong><%= metric_group.name %></strong></td>
          <td class="ck-meta-copy"><%= truncate(metric_group.description.to_s, length: 90).presence || "—" %></td>
          <td class="ck-meta-copy"><%= metric_group.metrics.any? ? metric_group.metrics.map(&:name).join(", ") : "empty" %></td>
          <td class="ck-results-table__arrow">&rarr;</td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% else %>
  <div class="ck-empty">
    <p>No metric groups yet. <%= link_to "Create one", new_metric_group_path, class: "ck-link" %> if you want to group multiple metrics and apply them together.</p>
  </div>
<% end %>
```

- [ ] **Step 3: Rewrite `app/views/completion_kit/metric_groups/_form.html.erb`**

```erb
<%= form_with(model: metric_group, url: metric_group.persisted? ? metric_group_path(metric_group) : metric_groups_path, local: true) do |form| %>
  <% if metric_group.errors.any? %>
    <div class="ck-flash ck-flash--alert">
      <p class="ck-flash__title"><%= pluralize(metric_group.errors.count, "problem") %> prevented this metric group from being saved.</p>
      <ul class="ck-error-list">
        <% metric_group.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div class="ck-card ck-form-card">
    <div class="ck-field">
      <%= form.label :name, "Metric group name", class: "ck-label" %>
      <%= form.text_field :name, class: "ck-input", placeholder: "Support quality" %>
    </div>

    <div class="ck-field">
      <%= form.label :description, class: "ck-label" %>
      <%= form.text_area :description, rows: 3, class: "ck-input ck-input--area", placeholder: "When this metric group should be used." %>
    </div>

    <div class="ck-field">
      <p class="ck-label">Metrics in this group</p>
      <p class="ck-hint">Group metrics together so you can apply them to a run as a set.</p>
      <div class="ck-list ck-list--compact">
        <% @metrics.each do |metric| %>
          <label class="ck-item">
            <span>
              <strong><%= metric.name %></strong>
              <span class="ck-meta-copy"><%= metric.instruction.presence || "No instruction set." %></span>
            </span>
            <%= check_box_tag "metric_group[metric_ids][]", metric.id, metric_group.metrics.exists?(metric.id), class: "ck-checkbox" %>
          </label>
        <% end %>
      </div>
      <%= hidden_field_tag "metric_group[metric_ids][]", "" %>
    </div>

    <div class="ck-actions">
      <%= link_to "Cancel", metrics_path, class: ck_button_classes(:light, variant: :outline) %>
      <%= form.submit(metric_group.persisted? ? "Save metric group" : "Create metric group", class: ck_button_classes(:dark)) %>
    </div>
  </div>
<% end %>
```

- [ ] **Step 4: Rewrite `app/views/completion_kit/metric_groups/new.html.erb`**

```erb
<ol class="ck-breadcrumb">
  <li><%= link_to "Metrics", metrics_path %></li>
  <li>New metric group</li>
</ol>

<section class="ck-page-header">
  <div>
    <h1 class="ck-title">New metric group</h1>
  </div>
</section>

<%= render "form", metric_group: @metric_group %>
```

- [ ] **Step 5: Rewrite `app/views/completion_kit/metric_groups/edit.html.erb`**

```erb
<ol class="ck-breadcrumb">
  <li><%= link_to "Metrics", metrics_path %></li>
  <li><%= link_to @metric_group.name, metric_group_path(@metric_group) %></li>
  <li>Edit</li>
</ol>

<section class="ck-page-header">
  <div>
    <h1 class="ck-title">Edit metric group</h1>
  </div>
</section>

<%= render "form", metric_group: @metric_group %>
```

- [ ] **Step 6: Rewrite `app/views/completion_kit/metric_groups/show.html.erb`**

```erb
<ol class="ck-breadcrumb">
  <li><%= link_to "Metrics", metrics_path %></li>
  <li><%= @metric_group.name %></li>
</ol>

<section class="ck-page-header">
  <div>
    <h1 class="ck-title"><%= @metric_group.name %></h1>
    <% if @metric_group.description.present? %>
      <p class="ck-lead"><%= @metric_group.description %></p>
    <% end %>
  </div>
  <div class="ck-actions">
    <%= link_to "Edit", edit_metric_group_path(@metric_group), class: ck_button_classes(:light, variant: :outline) %>
  </div>
</section>

<section class="ck-card">
  <p class="ck-kicker">Metrics</p>
  <% if @metric_group.metrics.any? %>
    <div class="ck-list ck-list--compact">
      <% @metric_group.metrics.each do |metric| %>
        <div class="ck-item">
          <div>
            <p class="ck-item-title"><%= link_to metric.name, metric_path(metric), class: "ck-link" %></p>
            <% if metric.instruction.present? %>
              <p class="ck-copy"><%= metric.instruction %></p>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
  <% else %>
    <p class="ck-copy">No metrics in this group yet.</p>
  <% end %>
</section>
```

---

## Task 9: Update cross-cutting views (metrics index, runs form, layout, API reference)

**Files:**
- Modify: `app/views/completion_kit/metrics/index.html.erb`
- Modify: `app/views/completion_kit/metrics_controller.rb` (association name)
- Modify: `app/controllers/completion_kit/metrics_controller.rb:7` — `Metric.includes(:criterias)` → `Metric.includes(:metric_groups)`
- Modify: `app/views/completion_kit/runs/_form.html.erb`
- Modify: `app/views/layouts/completion_kit/application.html.erb:22`
- Modify: `app/views/completion_kit/api_reference/index.html.erb`
- Modify: `app/controllers/completion_kit/runs_controller.rb` (if it references `@criterias`)

- [ ] **Step 1: Fix `metrics_controller.rb:7` include**

Replace:
```ruby
@metrics = Metric.includes(:criterias).order(:name)
```
with:
```ruby
@metrics = Metric.includes(:metric_groups).order(:name)
```

- [ ] **Step 2: Update `app/views/completion_kit/metrics/index.html.erb`**

Change line 26 from:
```erb
<td class="ck-meta-copy"><%= metric.criterias.any? ? metric.criterias.map(&:name).join(", ") : "—" %></td>
```
to:
```erb
<td class="ck-meta-copy"><%= metric.metric_groups.any? ? metric.metric_groups.map(&:name).join(", ") : "—" %></td>
```

Change line 35 (the footer hint) from:
```erb
Use the same metrics on multiple runs? <%= link_to "Bundle them into a criteria →", criteria_path, class: "ck-link" %>
```
to:
```erb
Use the same metrics on multiple runs? <%= link_to "Group them into a metric group →", metric_groups_path, class: "ck-link" %>
```

Also update the "Bundled in" column header if present — change to "In groups" (keep the column header consistent with the new concept). Look at current line 18-ish area for the `<th>` and adjust.

- [ ] **Step 3: Update `app/views/completion_kit/runs/_form.html.erb`**

Find the `@criterias` block (around line 73-79) and replace with `@metric_groups`. Rename the JS function `ckQuickAddCriteria` → `ckQuickAddMetricGroup` and update the `onclick` call site. Update the hint text "Select at least one metric or criteria to enable judging." → "Select at least one metric or group to enable judging.":

```erb
<% if @metric_groups.any? %>
  <p class="ck-meta-copy" style="margin-bottom: 0.5rem;">
    Quick add:&ensp;
    <% @metric_groups.each do |g| %>
      <span class="ck-chip" style="cursor: pointer;" onclick="ckQuickAddMetricGroup(<%= g.metric_ids.to_json %>)"><%= g.name %></span>&ensp;
    <% end %>
  </p>
<% end %>
```

And in the JS:
```js
function ckQuickAddMetricGroup(metricIds) {
  metricIds.forEach(function(id) {
    var cb = document.getElementById('run_metric_' + id);
    if (cb) cb.checked = true;
  });
  updateRunForm();
}
```

- [ ] **Step 4: Update `RunsController` if it assigns `@criterias`**

Grep `app/controllers/completion_kit/runs_controller.rb` for `@criterias` or `Criteria.` and replace with `@metric_groups` and `MetricGroup.`. If the controller currently does `@criterias = CompletionKit::Criteria.order(:name)`, change to `@metric_groups = CompletionKit::MetricGroup.order(:name)`.

- [ ] **Step 5: Update layout nav at `app/views/layouts/completion_kit/application.html.erb:22`**

Change:
```erb
<%= link_to "Metrics", metrics_path, class: request.path.start_with?(metrics_path) || request.path.start_with?(criteria_path) ? ck_button_classes(:dark) : ck_button_classes(:light, variant: :outline) %>
```
to:
```erb
<%= link_to "Metrics", metrics_path, class: request.path.start_with?(metrics_path) || request.path.start_with?(metric_groups_path) ? ck_button_classes(:dark) : ck_button_classes(:light, variant: :outline) %>
```

- [ ] **Step 6: Update API reference page**

In `app/views/completion_kit/api_reference/index.html.erb`:
- Line 66: `id="ck-tab-criteria"` → `id="ck-tab-metric-groups"`
- Line 76: `for="ck-tab-criteria"` → `for="ck-tab-metric-groups"`; label text "Criteria" → "Metric Groups"
- Line 245: `<h2 class="ck-section-title">Criteria</h2>` → `<h2 class="ck-section-title">Metric Groups</h2>`
- Line 246: "Named groups of metrics applied to runs as a set." (text is fine — keep or slightly tweak to "Named groups of metrics you can apply to a run as a set.")
- Line 248, 252, 257: `/api/v1/criteria` → `/api/v1/metric_groups`
- Line 249: "List all criteria with their metric IDs." → "List all metric groups with their metric IDs."
- Line 253: "Create a criteria group." → "Create a metric group."
- Line 258: "Get, update, or delete a criteria group." → "Get, update, or delete a metric group."

---

## Task 10: Rename MCP tools file and rewrite

**Files:**
- Move: `app/services/completion_kit/mcp_tools/criteria.rb` → `app/services/completion_kit/mcp_tools/metric_groups.rb`
- Modify: `app/services/completion_kit/mcp_dispatcher.rb:36, 47`

- [ ] **Step 1: `git mv`**

```bash
git mv app/services/completion_kit/mcp_tools/criteria.rb app/services/completion_kit/mcp_tools/metric_groups.rb
```

- [ ] **Step 2: Rewrite `app/services/completion_kit/mcp_tools/metric_groups.rb`**

```ruby
module CompletionKit
  module McpTools
    module MetricGroups
      TOOLS = {
        "metric_groups_list" => {
          description: "List all metric groups",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "metric_groups_get" => {
          description: "Get a metric group by ID",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "metric_groups_create" => {
          description: "Create a metric group",
          inputSchema: {
            type: "object",
            properties: {
              name: {type: "string"}, description: {type: "string"},
              metric_ids: {type: "array", items: {type: "integer"}}
            },
            required: ["name"]
          },
          handler: :create
        },
        "metric_groups_update" => {
          description: "Update a metric group",
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, name: {type: "string"}, description: {type: "string"},
              metric_ids: {type: "array", items: {type: "integer"}}
            },
            required: ["id"]
          },
          handler: :update
        },
        "metric_groups_delete" => {
          description: "Delete a metric group",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        }
      }.freeze

      def self.definitions
        TOOLS.map { |name, config| {name: name, description: config[:description], inputSchema: config[:inputSchema]} }
      end

      def self.call(name, arguments)
        tool = TOOLS.fetch(name)
        send(tool[:handler], arguments)
      end

      def self.list(_args)
        text_result(CompletionKit::MetricGroup.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(CompletionKit::MetricGroup.find(args["id"]).as_json)
      end

      def self.create(args)
        metric_group = CompletionKit::MetricGroup.new(args.slice("name", "description"))
        if metric_group.save
          replace_metric_memberships(metric_group, args["metric_ids"])
          text_result(metric_group.reload.as_json)
        else
          error_result(metric_group.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        metric_group = CompletionKit::MetricGroup.find(args["id"])
        if metric_group.update(args.except("id", "metric_ids").slice("name", "description"))
          replace_metric_memberships(metric_group, args["metric_ids"]) if args.key?("metric_ids")
          text_result(metric_group.reload.as_json)
        else
          error_result(metric_group.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        CompletionKit::MetricGroup.find(args["id"]).destroy!
        text_result("Metric group #{args["id"]} deleted")
      end

      def self.text_result(data)
        text = data.is_a?(String) ? data : data.to_json
        {content: [{type: "text", text: text}]}
      end

      def self.error_result(message)
        {content: [{type: "text", text: message}], isError: true}
      end

      def self.replace_metric_memberships(metric_group, metric_ids)
        return unless metric_ids
        metric_group.metric_group_memberships.delete_all
        Array(metric_ids).reject(&:blank?).each_with_index do |metric_id, index|
          metric_group.metric_group_memberships.create!(metric_id: metric_id, position: index + 1)
        end
      end
    end
  end
end
```

- [ ] **Step 3: Update `app/services/completion_kit/mcp_dispatcher.rb`**

Line 36 (in `tool_definitions`):
```ruby
McpTools::MetricGroups.definitions +
```

Line 47 (in `call_tool`):
```ruby
when /\Ametric_groups_/        then McpTools::MetricGroups.call(name, arguments)
```

Remove the old `McpTools::Criteria.definitions +` and `when /\Acriteria_/ then McpTools::Criteria.call(...)` lines.

---

## Task 11: Update the in-memory test schema in `rails_helper.rb`

**Files:**
- Modify: `spec/rails_helper.rb:47-51` and `spec/rails_helper.rb:61-66`

- [ ] **Step 1: Replace the two `create_table` blocks**

Replace:
```ruby
create_table :completion_kit_criteria, force: true do |t|
  t.string :name
  t.text :description
  t.timestamps
end
```
with:
```ruby
create_table :completion_kit_metric_groups, force: true do |t|
  t.string :name
  t.text :description
  t.timestamps
end
```

Replace:
```ruby
create_table :completion_kit_criteria_memberships, force: true do |t|
  t.references :criteria, null: false
  t.references :metric, null: false
  t.integer :position
  t.timestamps
end
```
with:
```ruby
create_table :completion_kit_metric_group_memberships, force: true do |t|
  t.references :metric_group, null: false
  t.references :metric, null: false
  t.integer :position
  t.timestamps
end
```

---

## Task 12: Rename spec files and rewrite them

**Files:**
- Move: `spec/models/completion_kit/criteria_spec.rb` → `spec/models/completion_kit/metric_group_spec.rb`
- Move: `spec/requests/completion_kit/criteria_spec.rb` → `spec/requests/completion_kit/metric_groups_spec.rb`
- Move: `spec/requests/completion_kit/api/v1/criteria_spec.rb` → `spec/requests/completion_kit/api/v1/metric_groups_spec.rb`
- Move: `spec/services/completion_kit/mcp_tools/criteria_spec.rb` → `spec/services/completion_kit/mcp_tools/metric_groups_spec.rb`

- [ ] **Step 1: `git mv` all four files**

```bash
git mv spec/models/completion_kit/criteria_spec.rb spec/models/completion_kit/metric_group_spec.rb
git mv spec/requests/completion_kit/criteria_spec.rb spec/requests/completion_kit/metric_groups_spec.rb
git mv spec/requests/completion_kit/api/v1/criteria_spec.rb spec/requests/completion_kit/api/v1/metric_groups_spec.rb
git mv spec/services/completion_kit/mcp_tools/criteria_spec.rb spec/services/completion_kit/mcp_tools/metric_groups_spec.rb
```

- [ ] **Step 2: Rewrite `spec/models/completion_kit/metric_group_spec.rb`**

```ruby
require "rails_helper"

RSpec.describe CompletionKit::MetricGroup, type: :model do
  it "orders metrics by membership position" do
    metric_group = create(:completion_kit_metric_group)
    later_metric = create(:completion_kit_metric, name: "Later")
    earlier_metric = create(:completion_kit_metric, name: "Earlier")
    create(:completion_kit_metric_group_membership, metric_group: metric_group, metric: later_metric, position: 2)
    create(:completion_kit_metric_group_membership, metric_group: metric_group, metric: earlier_metric, position: 1)

    expect(metric_group.ordered_metrics).to eq([earlier_metric, later_metric])
  end

  it "assigns a default position when one is not provided" do
    metric_group = create(:completion_kit_metric_group)
    membership = create(:completion_kit_metric_group_membership, metric_group: metric_group, position: nil)

    expect(membership.position).to eq(1)
  end
end
```

- [ ] **Step 3: Rewrite `spec/requests/completion_kit/metric_groups_spec.rb`**

```ruby
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
    expect(response.body).to include("Group metrics together")

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
end
```

- [ ] **Step 4: Rewrite `spec/requests/completion_kit/api/v1/metric_groups_spec.rb`**

```ruby
require "rails_helper"

RSpec.describe "API V1 Metric Groups", type: :request do
  let(:token) { "test-api-token" }
  let(:headers) { {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"} }

  before { CompletionKit.config.api_token = token }
  after { CompletionKit.instance_variable_set(:@config, nil) }

  describe "GET /api/v1/metric_groups" do
    it "returns all metric groups" do
      create(:completion_kit_metric_group)
      get "/completion_kit/api/v1/metric_groups", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).length).to eq(1)
    end
  end

  describe "GET /api/v1/metric_groups/:id" do
    it "returns the metric group with metric_ids" do
      metric_group = create(:completion_kit_metric_group, :with_metrics)
      get "/completion_kit/api/v1/metric_groups/#{metric_group.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["metric_ids"]).to be_an(Array)
      expect(body["metric_ids"].length).to be > 0
    end

    it "returns 404 for missing metric group" do
      get "/completion_kit/api/v1/metric_groups/999999", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/metric_groups" do
    it "creates a metric group with metrics" do
      metric = create(:completion_kit_metric)
      post "/completion_kit/api/v1/metric_groups",
        params: {name: "quality", metric_ids: [metric.id]}.to_json,
        headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["metric_ids"]).to eq([metric.id])
    end

    it "creates a metric group without metrics" do
      post "/completion_kit/api/v1/metric_groups",
        params: {name: "simple"}.to_json,
        headers: headers
      expect(response).to have_http_status(:created)
    end

    it "returns 422 with invalid params" do
      post "/completion_kit/api/v1/metric_groups", params: {name: ""}.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/metric_groups/:id" do
    it "updates a metric group" do
      metric_group = create(:completion_kit_metric_group)
      patch "/completion_kit/api/v1/metric_groups/#{metric_group.id}", params: {name: "updated"}.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["name"]).to eq("updated")
    end

    it "returns 422 with invalid params" do
      metric_group = create(:completion_kit_metric_group)
      patch "/completion_kit/api/v1/metric_groups/#{metric_group.id}", params: {name: ""}.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "replaces metric associations" do
      metric_group = create(:completion_kit_metric_group, :with_metrics)
      new_metric = create(:completion_kit_metric)
      patch "/completion_kit/api/v1/metric_groups/#{metric_group.id}",
        params: {metric_ids: [new_metric.id]}.to_json,
        headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["metric_ids"]).to eq([new_metric.id])
    end

    it "handles nil metric_ids" do
      metric_group = create(:completion_kit_metric_group, :with_metrics)
      patch "/completion_kit/api/v1/metric_groups/#{metric_group.id}",
        params: {name: "updated", metric_ids: nil}.to_json,
        headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /api/v1/metric_groups/:id" do
    it "deletes a metric group" do
      metric_group = create(:completion_kit_metric_group)
      delete "/completion_kit/api/v1/metric_groups/#{metric_group.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end
  end
end
```

- [ ] **Step 5: Rewrite `spec/services/completion_kit/mcp_tools/metric_groups_spec.rb`**

```ruby
require "rails_helper"

RSpec.describe CompletionKit::McpTools::MetricGroups do
  describe ".definitions" do
    it "returns 5 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(5)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        metric_groups_list metric_groups_get metric_groups_create metric_groups_update metric_groups_delete
      ])
    end
  end

  describe ".call" do
    let!(:metric_group) { create(:completion_kit_metric_group, name: "Quality") }

    it "lists metric groups" do
      result = described_class.call("metric_groups_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("Quality")
    end

    it "gets a metric group by id" do
      result = described_class.call("metric_groups_get", {"id" => metric_group.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(metric_group.id)
    end

    it "creates a metric group" do
      result = described_class.call("metric_groups_create", {"name" => "New Group"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("New Group")
    end

    it "creates a metric group with metric_ids" do
      metric = create(:completion_kit_metric)
      result = described_class.call("metric_groups_create", {"name" => "With Metrics", "metric_ids" => [metric.id]})
      content = JSON.parse(result[:content].first[:text])
      expect(content["metric_ids"]).to eq([metric.id])
    end

    it "updates a metric group" do
      result = described_class.call("metric_groups_update", {"id" => metric_group.id, "name" => "Updated"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Updated")
    end

    it "updates a metric group with metric_ids" do
      metric = create(:completion_kit_metric)
      result = described_class.call("metric_groups_update", {"id" => metric_group.id, "metric_ids" => [metric.id]})
      content = JSON.parse(result[:content].first[:text])
      expect(content["metric_ids"]).to eq([metric.id])
    end

    it "returns error on invalid create" do
      result = described_class.call("metric_groups_create", {"name" => ""})
      expect(result[:isError]).to be true
    end

    it "returns error on invalid update" do
      result = described_class.call("metric_groups_update", {"id" => metric_group.id, "name" => ""})
      expect(result[:isError]).to be true
    end

    it "deletes a metric group" do
      result = described_class.call("metric_groups_delete", {"id" => metric_group.id})
      expect(result[:content].first[:text]).to include("deleted")
    end
  end
end
```

---

## Task 13: Rename factories

**Files:**
- Move: `spec/factories/criteria.rb` → `spec/factories/metric_groups.rb`
- Move: `spec/factories/criteria_memberships.rb` → `spec/factories/metric_group_memberships.rb`

- [ ] **Step 1: `git mv` both files**

```bash
git mv spec/factories/criteria.rb spec/factories/metric_groups.rb
git mv spec/factories/criteria_memberships.rb spec/factories/metric_group_memberships.rb
```

- [ ] **Step 2: Rewrite `spec/factories/metric_groups.rb`**

```ruby
FactoryBot.define do
  factory :completion_kit_metric_group, class: "CompletionKit::MetricGroup" do
    name { "Support QA" }
    description { "Metrics for checking support-oriented responses." }

    trait :with_metrics do
      transient do
        metrics_count { 2 }
      end

      after(:create) do |metric_group, evaluator|
        create_list(:completion_kit_metric_group_membership, evaluator.metrics_count, metric_group: metric_group)
      end
    end
  end
end
```

- [ ] **Step 3: Rewrite `spec/factories/metric_group_memberships.rb`**

```ruby
FactoryBot.define do
  factory :completion_kit_metric_group_membership, class: "CompletionKit::MetricGroupMembership" do
    association :metric_group, factory: :completion_kit_metric_group
    association :metric, factory: :completion_kit_metric
    sequence(:position) { |n| n }
  end
end
```

---

## Task 14: Update seeds

**Files:**
- Modify: `standalone/db/seeds.rb:48, 52, 182-186, 191-195`

- [ ] **Step 1: Replace `CompletionKit::Criteria` with `CompletionKit::MetricGroup` and `CompletionKit::CriteriaMembership` with `CompletionKit::MetricGroupMembership`**

Use a Grep to find each block then rewrite:

Line ~48:
```ruby
criteria = CompletionKit::MetricGroup.find_or_create_by!(name: "Listing Quality") do |c|
```
Rename the local variable too for clarity:
```ruby
listing_group = CompletionKit::MetricGroup.find_or_create_by!(name: "Listing Quality") do |c|
```

Line ~52:
```ruby
CompletionKit::MetricGroupMembership.find_or_create_by!(metric_group: listing_group, metric: metric) do |cm|
```

Line ~182-186: same treatment — rename `summary_criteria` to `summary_group` and the `CriteriaMembership` call.

Line ~191-195: same for `neighbourhood_criteria` → `neighbourhood_group`.

Also update any description strings mentioning "criteria" that now refer to the entity (e.g. `"Assessment criteria for ..."`) — those are fine as generic English (the field is a description of the group's purpose). Leave them.

---

## Task 15: Update README, CHANGELOG, CONTRIBUTING

**Files:**
- Modify: `README.md:12, 114, 125`
- Modify: `README.md:21-24, 34`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: README body mentions (lines 12 and 114)**

Line 12: "Score each output with an LLM judge against criteria you define." — this is generic English ("criteria" as a common noun). **Leave it.** (See design doc "Out of scope" — landing-page-like generic English uses are not renames.)

Line 114: same generic English — **leave it.**

- [ ] **Step 2: README Concepts section (line 125)**

Replace:
```markdown
- **Criteria.** A reusable bundle of metrics.
```
with:
```markdown
- **Metric Group.** A reusable group of metrics you can apply to a run as a set.
```

- [ ] **Step 3: README lines 21-24 and 34**

Line 21-24 in README (the "Prompts, Runs, Datasets, Metrics, and Criteria" sentence) — if this text exists in README, replace "Criteria" with "Metric Groups". Actually this appears in CHANGELOG, not README. Confirm by grepping README — if not present, skip.

Line 34 is in CHANGELOG (see next step).

- [ ] **Step 4: CHANGELOG — update the `[0.1.0.rc1]` entry text AND add `[Unreleased]` entry**

The `[0.1.0.rc1]` entry has already shipped; historically it used the name "Criteria". That's a historical release note — **leave it unchanged** (the gem was published under that name).

Add under `[Unreleased]`:
```markdown
## [Unreleased]

### Changed

- **Breaking:** `Criteria` renamed to `Metric Group` across the entire product.
  REST API paths `/api/v1/criteria` → `/api/v1/metric_groups`. MCP tools
  `criteria_*` → `metric_groups_*`. Ruby class `CompletionKit::Criteria` →
  `CompletionKit::MetricGroup`, `CompletionKit::CriteriaMembership` →
  `CompletionKit::MetricGroupMembership`. Web routes `/completion_kit/criteria` →
  `/completion_kit/metric_groups`. Database tables renamed in place; no
  data migration needed. No backwards-compatibility aliases.
```

- [ ] **Step 5: CONTRIBUTING.md**

Grep already returned no matches — nothing to do.

---

## Task 16: Install migration into standalone

**Files:**
- Create: `standalone/db/migrate/<timestamp>_rename_criteria_to_metric_groups.completion_kit.rb` (via Rails task)

- [ ] **Step 1: Run the install task**

```bash
cd standalone && bin/rails completion_kit:install:migrations
```

Expected output line: `Copied migration YYYYMMDDHHMMSS_rename_criteria_to_metric_groups.completion_kit.rb from completion_kit`.

- [ ] **Step 2: Verify the file is present**

```bash
ls standalone/db/migrate/*rename_criteria*
```

Expected: exactly one file matching the pattern.

---

## Task 17: Update memory files

**Files:**
- Modify: memory files under `/Users/damien/.claude/projects/-Users-damien-Work-homemade-completion-kit/memory/` that mention Criteria

- [ ] **Step 1: Grep memory for Criteria references**

```bash
grep -rln "Criteria\|criteria_\|CriteriaMembership" /Users/damien/.claude/projects/-Users-damien-Work-homemade-completion-kit/memory/
```

- [ ] **Step 2: Update each match**

For each file that matches, replace entity references with the new names (MetricGroup, metric_groups, MetricGroupMembership). These are live memory for future conversations — they should reflect the current state. Leave generic English uses ("criteria you define") alone.

If `project_rest_api.md` lists `/api/v1/criteria`, update to `/api/v1/metric_groups`.
If `project_mcp_server.md` lists `criteria_*` tools, update to `metric_groups_*`.

---

## Task 18: Run the full suite

- [ ] **Step 1: Run RSpec from the engine root**

```bash
bundle exec rspec
```

Expected: all specs pass. 100% line and branch coverage maintained.

If failures: grep the error for the failing file, fix the reference, re-run. Common sources:

- `NameError: uninitialized constant CompletionKit::Criteria` — something still references the old constant. Grep and fix.
- `ActionController::UrlGenerationError` — a path helper (`criterion_path`, `criteria_path`) still in use. Find the view/controller and replace with `metric_group_path` / `metric_groups_path`.
- `ActiveRecord::StatementInvalid: SQLite3::SQLException: no such table: completion_kit_criteria` — the in-memory test schema still declares the old table name. Re-check Task 11.
- Factory errors — Task 13 not complete.

- [ ] **Step 2: Grep for leftover references**

```bash
grep -rn "Criteria\|CriteriaMembership\|criteria_memberships\|criterion_path\|criteria_path" app/ lib/ spec/ config/ standalone/db/seeds.rb
```

Expected: zero matches (ignore the spec dir for the design doc and any generic English that survives in README/CHANGELOG historical entries).

If any matches appear in `app/`, `lib/`, `spec/`, or `config/`, fix them and re-run the suite.

---

## Task 19: Boot the app in dev + smoke test

- [ ] **Step 1: Start the server**

```bash
cd standalone && bin/rails s
```

Expected: boots without error.

- [ ] **Step 2: Visit key URLs**

- `http://localhost:3000/completion_kit/metric_groups` → 200, shows index
- `http://localhost:3000/completion_kit/metrics` → 200, footer hint links to `/metric_groups`
- `http://localhost:3000/completion_kit/criteria` → 404 (no redirect)
- `http://localhost:3000/completion_kit/api_reference` → 200, tab labelled "Metric Groups"

Stop the server.

---

## Task 20: Commit + push + deploy

- [ ] **Step 1: Review diff**

```bash
git status
git diff --stat
```

Confirm all renames landed. No stray changes.

- [ ] **Step 2: Stage and commit**

```bash
git add -A
git commit -m "rename Criteria to MetricGroup (breaking)"
```

- [ ] **Step 3: Push**

```bash
git push origin main
```

- [ ] **Step 4: CI gate**

Wait for GitHub Actions to go green. If CI fails, fix locally, push again. (Do not skip hooks.)

- [ ] **Step 5: Watch Render pre-deploy**

Render auto-deploys from `main`. Pre-deploy runs `bin/rails db:migrate` which executes the engine migration against Supabase. If Render's auto-deploy stalls (we've seen this before), trigger a manual deploy from the Render dashboard.

---

## Task 21: Post-deploy verification

- [ ] **Step 1: Verify Supabase tables via MCP**

Use `mcp__supabase__list_tables` on project `jrnxliafsjlzknidzmks`. Expected:

- `completion_kit_metric_groups` exists with 1 row
- `completion_kit_metric_group_memberships` exists with 3 rows and a `metric_group_id` column
- `completion_kit_criteria` and `completion_kit_criteria_memberships` DO NOT exist

- [ ] **Step 2: RLS advisor check**

```
mcp__supabase__get_advisors(type: "security")
```

Expected: no new `rls_disabled_in_public` ERROR for the renamed tables. (Postgres `rename_table` preserves RLS state — this is a sanity check.)

If a new RLS error appears on one of the renamed tables, apply `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` via `mcp__supabase__execute_sql` and commit a follow-up note to the deployment-topology memory.

- [ ] **Step 3: Smoke test production**

- `https://<prod-host>/completion_kit/metric_groups` → 200, renders existing metric group
- `https://<prod-host>/completion_kit/criteria` → 404
- `curl -H "Authorization: Bearer $TOKEN" https://<prod-host>/completion_kit/api/v1/metric_groups` → JSON list
- `curl -H "Authorization: Bearer $TOKEN" https://<prod-host>/completion_kit/api/v1/criteria` → 404

---

## Rollback

If production breaks after deploy:

1. `git revert <rename-commit>` on `main`, push. Render deploys the revert; pre-deploy runs the down migration (`rename_table` reverses cleanly).
2. Or, faster: `bin/rails db:rollback` in the Render shell, then revert the code commit on GitHub.

Both options are covered by the fully reversible migration.
