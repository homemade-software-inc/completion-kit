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

ActiveRecord::Schema[7.2].define(version: 2026_03_11_214724) do
  create_table "completion_kit_criteria", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "completion_kit_criteria_memberships", force: :cascade do |t|
    t.integer "criteria_id", null: false
    t.integer "metric_id", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["criteria_id"], name: "index_completion_kit_criteria_memberships_on_criteria_id"
    t.index ["metric_id"], name: "index_completion_kit_criteria_memberships_on_metric_id"
  end

  create_table "completion_kit_datasets", force: :cascade do |t|
    t.string "name", null: false
    t.text "csv_data", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "completion_kit_metrics", force: :cascade do |t|
    t.string "name", null: false
    t.text "criteria"
    t.text "evaluation_steps"
    t.text "rubric_bands"
    t.string "key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_completion_kit_metrics_on_key", unique: true
  end

  create_table "completion_kit_prompts", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.text "template", null: false
    t.string "llm_model", null: false
    t.string "family_key", null: false
    t.integer "version_number", null: false
    t.boolean "current", default: true, null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["family_key", "current"], name: "idx_ck_prompts_family_current"
    t.index ["family_key", "version_number"], name: "idx_ck_prompts_family_version", unique: true
    t.index ["family_key"], name: "index_completion_kit_prompts_on_family_key"
  end

  create_table "completion_kit_provider_credentials", force: :cascade do |t|
    t.string "provider", null: false
    t.text "api_key"
    t.text "api_endpoint"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider"], name: "index_completion_kit_provider_credentials_on_provider", unique: true
  end

  create_table "completion_kit_responses", force: :cascade do |t|
    t.integer "run_id", null: false
    t.text "input_data"
    t.text "response_text"
    t.text "expected_output"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["run_id"], name: "index_completion_kit_responses_on_run_id"
  end

  create_table "completion_kit_reviews", force: :cascade do |t|
    t.integer "response_id", null: false
    t.integer "metric_id"
    t.string "metric_name"
    t.text "criteria"
    t.string "status"
    t.decimal "ai_score", precision: 4, scale: 1
    t.text "ai_feedback"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["metric_id"], name: "index_completion_kit_reviews_on_metric_id"
    t.index ["response_id"], name: "index_completion_kit_reviews_on_response_id"
  end

  create_table "completion_kit_runs", force: :cascade do |t|
    t.string "name"
    t.integer "prompt_id", null: false
    t.integer "dataset_id"
    t.integer "criteria_id"
    t.string "judge_model"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["criteria_id"], name: "index_completion_kit_runs_on_criteria_id"
    t.index ["dataset_id"], name: "index_completion_kit_runs_on_dataset_id"
    t.index ["prompt_id"], name: "index_completion_kit_runs_on_prompt_id"
  end

  add_foreign_key "completion_kit_criteria_memberships", "completion_kit_criteria", column: "criteria_id"
  add_foreign_key "completion_kit_criteria_memberships", "completion_kit_metrics", column: "metric_id"
  add_foreign_key "completion_kit_responses", "completion_kit_runs", column: "run_id"
  add_foreign_key "completion_kit_reviews", "completion_kit_metrics", column: "metric_id"
  add_foreign_key "completion_kit_reviews", "completion_kit_responses", column: "response_id"
  add_foreign_key "completion_kit_runs", "completion_kit_criteria", column: "criteria_id"
  add_foreign_key "completion_kit_runs", "completion_kit_datasets", column: "dataset_id"
  add_foreign_key "completion_kit_runs", "completion_kit_prompts", column: "prompt_id"
end
