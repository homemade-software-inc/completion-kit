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

ActiveRecord::Schema[8.1].define(version: 2026_04_04_013536) do
  create_table "completion_kit_criteria", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "completion_kit_criteria_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "criteria_id", null: false
    t.integer "metric_id", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["criteria_id"], name: "index_completion_kit_criteria_memberships_on_criteria_id"
    t.index ["metric_id"], name: "index_completion_kit_criteria_memberships_on_metric_id"
  end

  create_table "completion_kit_datasets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "csv_data", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "completion_kit_metrics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "evaluation_steps"
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
    t.string "discovery_status"
    t.integer "discovery_total", default: 0
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["provider"], name: "index_completion_kit_provider_credentials_on_provider", unique: true
  end

  create_table "completion_kit_responses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "expected_output"
    t.text "input_data"
    t.text "response_text"
    t.integer "run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["run_id"], name: "index_completion_kit_responses_on_run_id"
  end

  create_table "completion_kit_reviews", force: :cascade do |t|
    t.text "ai_feedback"
    t.decimal "ai_score", precision: 4, scale: 1
    t.datetime "created_at", null: false
    t.text "instruction"
    t.integer "metric_id"
    t.string "metric_name"
    t.integer "response_id", null: false
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["metric_id"], name: "index_completion_kit_reviews_on_metric_id"
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
    t.string "judge_model"
    t.string "name"
    t.integer "progress_current", default: 0
    t.integer "progress_total", default: 0
    t.integer "prompt_id", null: false
    t.string "status"
    t.float "temperature", default: 0.7
    t.datetime "updated_at", null: false
    t.index ["dataset_id"], name: "index_completion_kit_runs_on_dataset_id"
    t.index ["prompt_id"], name: "index_completion_kit_runs_on_prompt_id"
  end

  create_table "completion_kit_suggestions", force: :cascade do |t|
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

  add_foreign_key "completion_kit_criteria_memberships", "completion_kit_criteria", column: "criteria_id"
  add_foreign_key "completion_kit_criteria_memberships", "completion_kit_metrics", column: "metric_id"
  add_foreign_key "completion_kit_responses", "completion_kit_runs", column: "run_id"
  add_foreign_key "completion_kit_reviews", "completion_kit_metrics", column: "metric_id"
  add_foreign_key "completion_kit_reviews", "completion_kit_responses", column: "response_id"
  add_foreign_key "completion_kit_run_metrics", "completion_kit_metrics", column: "metric_id"
  add_foreign_key "completion_kit_run_metrics", "completion_kit_runs", column: "run_id"
  add_foreign_key "completion_kit_runs", "completion_kit_datasets", column: "dataset_id"
  add_foreign_key "completion_kit_runs", "completion_kit_prompts", column: "prompt_id"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
