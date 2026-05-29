# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_29_232016) do
  create_table "completion_kit_calibrations", force: :cascade do |t|
    t.decimal "corrected_score", precision: 4, scale: 1
    t.datetime "created_at", null: false
    t.string "created_by"
    t.integer "metric_id", null: false
    t.integer "metric_version_id", null: false
    t.text "note"
    t.integer "response_id", null: false
    t.integer "run_id", null: false
    t.datetime "updated_at", null: false
    t.string "verdict", null: false
    t.index ["metric_id"], name: "index_ck_calibrations_on_metric_id"
    t.index ["metric_version_id"], name: "index_ck_calibrations_on_metric_version_id"
    t.index ["response_id", "metric_id", "created_by"], name: "index_ck_calibrations_on_response_metric_user", unique: true
    t.index ["response_id"], name: "index_ck_calibrations_on_response_id"
    t.index ["run_id"], name: "index_ck_calibrations_on_run_id"
  end

  create_table "completion_kit_dashboard_dismissals", force: :cascade do |t|
    t.decimal "baseline_score", precision: 4, scale: 1
    t.datetime "created_at", null: false
    t.bigint "dismissable_id", null: false
    t.string "dismissable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["dismissable_type", "dismissable_id"], name: "index_ck_dashboard_dismissals_on_dismissable", unique: true
  end

  create_table "completion_kit_datasets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "csv_data", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "completion_kit_mcp_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_completion_kit_mcp_sessions_on_expires_at"
    t.index ["session_id"], name: "index_completion_kit_mcp_sessions_on_session_id", unique: true
  end

  create_table "completion_kit_metric_group_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "metric_group_id", null: false
    t.integer "metric_id", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["metric_group_id"], name: "idx_on_metric_group_id_10d87ecba5"
    t.index ["metric_id"], name: "index_completion_kit_metric_group_memberships_on_metric_id"
  end

  create_table "completion_kit_metric_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "completion_kit_metric_versions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "current", default: true, null: false
    t.text "instruction"
    t.integer "metric_id", null: false
    t.datetime "published_at"
    t.text "rubric_bands"
    t.string "source"
    t.string "state", default: "published", null: false
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["metric_id", "current"], name: "index_ck_metric_versions_on_metric_current"
    t.index ["metric_id", "state"], name: "index_ck_metric_versions_on_metric_state"
    t.index ["metric_id", "version_number"], name: "index_ck_metric_versions_on_metric_vnum"
    t.index ["metric_id"], name: "index_ck_metric_versions_on_metric_id"
  end

  create_table "completion_kit_metrics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "instruction"
    t.string "key"
    t.string "name", null: false
    t.text "rubric_bands"
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_completion_kit_metrics_on_key", unique: true
  end

  create_table "completion_kit_models", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "discovered_at"
    t.string "display_name"
    t.text "generation_error"
    t.text "judging_error"
    t.string "model_id", null: false
    t.datetime "probed_at"
    t.string "provider", null: false
    t.datetime "retired_at"
    t.string "status", default: "active", null: false
    t.boolean "supports_generation"
    t.boolean "supports_judging"
    t.datetime "updated_at", null: false
    t.index ["provider", "model_id"], name: "index_completion_kit_models_on_provider_and_model_id", unique: true
  end

  create_table "completion_kit_prompts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "current", default: true, null: false
    t.text "description"
    t.string "family_key", null: false
    t.string "llm_model", null: false
    t.string "name", null: false
    t.datetime "published_at"
    t.text "template", null: false
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["family_key", "current"], name: "idx_ck_prompts_family_current"
    t.index ["family_key", "version_number"], name: "idx_ck_prompts_family_version", unique: true
    t.index ["family_key"], name: "index_completion_kit_prompts_on_family_key"
  end

  create_table "completion_kit_provider_credentials", force: :cascade do |t|
    t.text "api_endpoint"
    t.text "api_key"
    t.datetime "created_at", null: false
    t.integer "discovery_current", default: 0
    t.text "discovery_error"
    t.string "discovery_status"
    t.integer "discovery_total", default: 0
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["provider"], name: "index_completion_kit_provider_credentials_on_provider", unique: true
  end

  create_table "completion_kit_responses", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "error_class"
    t.text "error_message"
    t.string "error_provider"
    t.integer "error_status"
    t.text "expected_output"
    t.text "input_data"
    t.text "response_text"
    t.integer "row_index"
    t.integer "run_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["run_id", "status"], name: "index_completion_kit_responses_on_run_id_and_status"
    t.index ["run_id"], name: "index_completion_kit_responses_on_run_id"
  end

  create_table "completion_kit_reviews", force: :cascade do |t|
    t.text "ai_feedback"
    t.decimal "ai_score", precision: 4, scale: 1
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "error_class"
    t.text "error_message"
    t.string "error_provider"
    t.integer "error_status"
    t.text "instruction"
    t.integer "metric_id"
    t.string "metric_name"
    t.bigint "metric_version_id"
    t.integer "response_id", null: false
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["metric_id"], name: "index_completion_kit_reviews_on_metric_id"
    t.index ["metric_version_id"], name: "index_ck_reviews_on_metric_version_id"
    t.index ["response_id", "status"], name: "index_completion_kit_reviews_on_response_id_and_status"
    t.index ["response_id"], name: "index_completion_kit_reviews_on_response_id"
  end

  create_table "completion_kit_run_metrics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "metric_id", null: false
    t.integer "position"
    t.integer "run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["metric_id"], name: "index_completion_kit_run_metrics_on_metric_id"
    t.index ["run_id"], name: "index_completion_kit_run_metrics_on_run_id"
  end

  create_table "completion_kit_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "dataset_id"
    t.text "error_message"
    t.text "failure_summary"
    t.string "judge_model"
    t.string "name"
    t.string "output_column"
    t.integer "progress_current", default: 0
    t.integer "progress_total", default: 0
    t.integer "prompt_id"
    t.string "status"
    t.float "temperature", default: 0.7
    t.boolean "temperature_ignored", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["dataset_id"], name: "index_completion_kit_runs_on_dataset_id"
    t.index ["prompt_id"], name: "index_completion_kit_runs_on_prompt_id"
  end

  create_table "completion_kit_starter_metric_dismissals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "starter_key", null: false
    t.datetime "updated_at", null: false
    t.index ["starter_key"], name: "index_ck_starter_dismissals_on_key", unique: true
  end

  create_table "completion_kit_suggestions", force: :cascade do |t|
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.text "original_template"
    t.integer "prompt_id", null: false
    t.text "reasoning"
    t.integer "run_id", null: false
    t.text "suggested_template"
    t.datetime "updated_at", null: false
    t.index ["prompt_id"], name: "index_completion_kit_suggestions_on_prompt_id"
    t.index ["run_id"], name: "index_completion_kit_suggestions_on_run_id"
  end

  create_table "completion_kit_taggings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "tag_id", null: false
    t.bigint "taggable_id", null: false
    t.string "taggable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_id", "taggable_type", "taggable_id"], name: "idx_taggings_unique", unique: true
    t.index ["tag_id"], name: "index_completion_kit_taggings_on_tag_id"
    t.index ["taggable_type", "taggable_id"], name: "index_completion_kit_taggings_on_taggable_type_and_taggable_id"
  end

  create_table "completion_kit_tags", force: :cascade do |t|
    t.string "color", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_completion_kit_tags_on_name", unique: true
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", limit: 1024, null: false
    t.integer "channel_hash", limit: 8, null: false
    t.datetime "created_at", null: false
    t.binary "payload", limit: 536870912, null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  add_foreign_key "completion_kit_calibrations", "completion_kit_metric_versions", column: "metric_version_id", on_delete: :cascade
  add_foreign_key "completion_kit_calibrations", "completion_kit_metrics", column: "metric_id", on_delete: :cascade
  add_foreign_key "completion_kit_calibrations", "completion_kit_responses", column: "response_id", on_delete: :cascade
  add_foreign_key "completion_kit_calibrations", "completion_kit_runs", column: "run_id", on_delete: :cascade
  add_foreign_key "completion_kit_metric_group_memberships", "completion_kit_metric_groups", column: "metric_group_id"
  add_foreign_key "completion_kit_metric_group_memberships", "completion_kit_metrics", column: "metric_id"
  add_foreign_key "completion_kit_metric_versions", "completion_kit_metrics", column: "metric_id", on_delete: :cascade
  add_foreign_key "completion_kit_responses", "completion_kit_runs", column: "run_id"
  add_foreign_key "completion_kit_reviews", "completion_kit_metrics", column: "metric_id"
  add_foreign_key "completion_kit_reviews", "completion_kit_responses", column: "response_id"
  add_foreign_key "completion_kit_run_metrics", "completion_kit_metrics", column: "metric_id"
  add_foreign_key "completion_kit_run_metrics", "completion_kit_runs", column: "run_id"
  add_foreign_key "completion_kit_runs", "completion_kit_datasets", column: "dataset_id"
  add_foreign_key "completion_kit_runs", "completion_kit_prompts", column: "prompt_id"
  add_foreign_key "completion_kit_taggings", "completion_kit_tags", column: "tag_id"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
