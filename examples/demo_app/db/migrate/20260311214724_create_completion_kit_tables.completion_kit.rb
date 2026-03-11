# This migration comes from completion_kit (originally 20260311000001)
class CreateCompletionKitTables < ActiveRecord::Migration[7.1]
  def change
    create_table :completion_kit_prompts do |t|
      t.string :name, null: false
      t.text :description
      t.text :template, null: false
      t.string :llm_model, null: false
      t.string :family_key, null: false
      t.integer :version_number, null: false
      t.boolean :current, default: true, null: false
      t.datetime :published_at
      t.timestamps
    end

    add_index :completion_kit_prompts, :family_key
    add_index :completion_kit_prompts, [:family_key, :version_number], unique: true, name: "idx_ck_prompts_family_version"
    add_index :completion_kit_prompts, [:family_key, :current], name: "idx_ck_prompts_family_current"

    create_table :completion_kit_datasets do |t|
      t.string :name, null: false
      t.text :csv_data, null: false
      t.timestamps
    end

    create_table :completion_kit_metric_groups do |t|
      t.string :name, null: false
      t.text :description
      t.timestamps
    end

    create_table :completion_kit_metrics do |t|
      t.string :name, null: false
      t.text :criteria
      t.text :evaluation_steps
      t.text :rubric_bands
      t.string :key
      t.timestamps
    end

    add_index :completion_kit_metrics, :key, unique: true

    create_table :completion_kit_metric_group_memberships do |t|
      t.references :metric_group, null: false, foreign_key: { to_table: :completion_kit_metric_groups }
      t.references :metric, null: false, foreign_key: { to_table: :completion_kit_metrics }
      t.integer :position
      t.timestamps
    end

    create_table :completion_kit_provider_credentials do |t|
      t.string :provider, null: false
      t.text :api_key
      t.text :api_endpoint
      t.timestamps
    end

    add_index :completion_kit_provider_credentials, :provider, unique: true

    create_table :completion_kit_runs do |t|
      t.string :name
      t.references :prompt, null: false, foreign_key: { to_table: :completion_kit_prompts }
      t.references :dataset, foreign_key: { to_table: :completion_kit_datasets }
      t.references :metric_group, foreign_key: { to_table: :completion_kit_metric_groups }
      t.string :judge_model
      t.string :status
      t.timestamps
    end

    create_table :completion_kit_responses do |t|
      t.references :run, null: false, foreign_key: { to_table: :completion_kit_runs }
      t.text :input_data
      t.text :response_text
      t.text :expected_output
      t.timestamps
    end

    create_table :completion_kit_reviews do |t|
      t.references :response, null: false, foreign_key: { to_table: :completion_kit_responses }
      t.references :metric, foreign_key: { to_table: :completion_kit_metrics }
      t.string :metric_name
      t.text :criteria
      t.string :status
      t.decimal :ai_score, precision: 4, scale: 1
      t.text :ai_feedback
      t.timestamps
    end
  end
end
