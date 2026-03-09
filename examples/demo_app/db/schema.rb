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

ActiveRecord::Schema[7.2].define(version: 2026_03_09_022610) do
  create_table "completion_kit_metric_group_memberships", force: :cascade do |t|
    t.integer "metric_group_id", null: false
    t.integer "metric_id", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["metric_group_id"], name: "idx_on_metric_group_id_10d87ecba5"
    t.index ["metric_id"], name: "index_completion_kit_metric_group_memberships_on_metric_id"
  end

  create_table "completion_kit_metric_groups", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "completion_kit_metric_sets", force: :cascade do |t|
    t.string "name", null: false
    t.text "guidance_text"
    t.text "rubric_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "completion_kit_metrics", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.text "guidance_text"
    t.text "rubric_text"
    t.text "rubric_bands"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "completion_kit_prompts", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.text "template"
    t.string "llm_model"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "family_key", null: false
    t.integer "version_number", null: false
    t.boolean "current", default: true, null: false
    t.string "assessment_model"
    t.text "review_guidance"
    t.text "rubric_text"
    t.datetime "published_at"
    t.integer "metric_set_id"
    t.text "rubric_bands"
    t.integer "metric_group_id"
    t.index ["family_key", "current"], name: "idx_completion_kit_prompts_family_current"
    t.index ["family_key", "version_number"], name: "idx_completion_kit_prompts_family_version", unique: true
    t.index ["family_key"], name: "index_completion_kit_prompts_on_family_key"
    t.index ["metric_group_id"], name: "index_completion_kit_prompts_on_metric_group_id"
    t.index ["metric_set_id"], name: "index_completion_kit_prompts_on_metric_set_id"
  end

  create_table "completion_kit_provider_credentials", force: :cascade do |t|
    t.string "provider", null: false
    t.text "api_key"
    t.text "api_endpoint"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider"], name: "index_completion_kit_provider_credentials_on_provider", unique: true
  end

  create_table "completion_kit_test_result_metric_assessments", force: :cascade do |t|
    t.integer "test_result_id", null: false
    t.integer "metric_id"
    t.string "metric_name"
    t.text "guidance_text"
    t.text "rubric_text"
    t.string "status"
    t.decimal "ai_score", precision: 4, scale: 1
    t.text "ai_feedback"
    t.decimal "human_score", precision: 4, scale: 1
    t.text "human_feedback"
    t.string "human_reviewer_name"
    t.datetime "human_reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["metric_id"], name: "idx_on_metric_id_d07a6c508c"
    t.index ["test_result_id"], name: "idx_on_test_result_id_5c8f92f143"
  end

  create_table "completion_kit_test_results", force: :cascade do |t|
    t.integer "test_run_id", null: false
    t.string "status"
    t.text "input_data"
    t.text "output_text"
    t.text "expected_output"
    t.text "judge_feedback"
    t.decimal "quality_score", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "human_score", precision: 4, scale: 1
    t.text "human_feedback"
    t.string "human_reviewer_name"
    t.datetime "human_reviewed_at"
    t.index ["test_run_id"], name: "index_completion_kit_test_results_on_test_run_id"
  end

  create_table "completion_kit_test_runs", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.integer "prompt_id", null: false
    t.text "csv_data"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["prompt_id"], name: "index_completion_kit_test_runs_on_prompt_id"
  end

  add_foreign_key "completion_kit_metric_group_memberships", "completion_kit_metric_groups", column: "metric_group_id"
  add_foreign_key "completion_kit_metric_group_memberships", "completion_kit_metrics", column: "metric_id"
  add_foreign_key "completion_kit_prompts", "completion_kit_metric_groups", column: "metric_group_id"
  add_foreign_key "completion_kit_prompts", "completion_kit_metric_sets", column: "metric_set_id"
  add_foreign_key "completion_kit_test_result_metric_assessments", "completion_kit_metrics", column: "metric_id"
  add_foreign_key "completion_kit_test_result_metric_assessments", "completion_kit_test_results", column: "test_result_id"
  add_foreign_key "completion_kit_test_results", "completion_kit_test_runs", column: "test_run_id"
  add_foreign_key "completion_kit_test_runs", "completion_kit_prompts", column: "prompt_id"
end
