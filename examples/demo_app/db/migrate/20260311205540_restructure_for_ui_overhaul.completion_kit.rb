# This migration comes from completion_kit (originally 20260311000001)
class RestructureForUiOverhaul < ActiveRecord::Migration[7.1]
  def up
    add_column :completion_kit_test_runs, :dataset_id, :integer
    add_column :completion_kit_test_runs, :judge_model, :string
    unless column_exists?(:completion_kit_test_runs, :metric_group_id)
      add_column :completion_kit_test_runs, :metric_group_id, :integer
    end

    execute <<~SQL
      INSERT INTO completion_kit_datasets (name, csv_data, created_at, updated_at)
      SELECT DISTINCT
        'Dataset from run ' || completion_kit_test_runs.id,
        completion_kit_test_runs.csv_data,
        completion_kit_test_runs.created_at,
        completion_kit_test_runs.updated_at
      FROM completion_kit_test_runs
      WHERE completion_kit_test_runs.csv_data IS NOT NULL
        AND completion_kit_test_runs.csv_data != ''
    SQL

    execute <<~SQL
      UPDATE completion_kit_test_runs
      SET dataset_id = (
        SELECT completion_kit_datasets.id
        FROM completion_kit_datasets
        WHERE completion_kit_datasets.csv_data = completion_kit_test_runs.csv_data
        LIMIT 1
      )
      WHERE completion_kit_test_runs.csv_data IS NOT NULL
        AND completion_kit_test_runs.csv_data != ''
    SQL

    if column_exists?(:completion_kit_prompts, :assessment_model)
      execute <<~SQL
        UPDATE completion_kit_test_runs
        SET judge_model = (
          SELECT completion_kit_prompts.assessment_model
          FROM completion_kit_prompts
          WHERE completion_kit_prompts.id = completion_kit_test_runs.prompt_id
        )
      SQL
    end

    if column_exists?(:completion_kit_prompts, :metric_group_id)
      execute <<~SQL
        UPDATE completion_kit_test_runs
        SET metric_group_id = (
          SELECT completion_kit_prompts.metric_group_id
          FROM completion_kit_prompts
          WHERE completion_kit_prompts.id = completion_kit_test_runs.prompt_id
        )
      SQL
    end

    rename_column :completion_kit_test_results, :output_text, :response_text

    if column_exists?(:completion_kit_test_results, :quality_score)
      remove_column :completion_kit_test_results, :quality_score
    end
    if column_exists?(:completion_kit_test_results, :human_score)
      remove_column :completion_kit_test_results, :human_score
    end
    if column_exists?(:completion_kit_test_results, :judge_feedback)
      remove_column :completion_kit_test_results, :judge_feedback
    end
    if column_exists?(:completion_kit_test_results, :human_feedback)
      remove_column :completion_kit_test_results, :human_feedback
    end
    if column_exists?(:completion_kit_test_results, :human_reviewer_name)
      remove_column :completion_kit_test_results, :human_reviewer_name
    end
    if column_exists?(:completion_kit_test_results, :human_reviewed_at)
      remove_column :completion_kit_test_results, :human_reviewed_at
    end
    if column_exists?(:completion_kit_test_results, :status)
      remove_column :completion_kit_test_results, :status
    end

    if column_exists?(:completion_kit_test_result_metric_assessments, :human_score)
      remove_column :completion_kit_test_result_metric_assessments, :human_score
    end
    if column_exists?(:completion_kit_test_result_metric_assessments, :human_feedback)
      remove_column :completion_kit_test_result_metric_assessments, :human_feedback
    end
    if column_exists?(:completion_kit_test_result_metric_assessments, :human_reviewer_name)
      remove_column :completion_kit_test_result_metric_assessments, :human_reviewer_name
    end
    if column_exists?(:completion_kit_test_result_metric_assessments, :human_reviewed_at)
      remove_column :completion_kit_test_result_metric_assessments, :human_reviewed_at
    end
    if column_exists?(:completion_kit_test_result_metric_assessments, :rubric_text)
      remove_column :completion_kit_test_result_metric_assessments, :rubric_text
    end

    if column_exists?(:completion_kit_prompts, :assessment_model)
      remove_column :completion_kit_prompts, :assessment_model
    end
    if column_exists?(:completion_kit_prompts, :review_guidance)
      remove_column :completion_kit_prompts, :review_guidance
    end
    if column_exists?(:completion_kit_prompts, :rubric_text)
      remove_column :completion_kit_prompts, :rubric_text
    end
    if column_exists?(:completion_kit_prompts, :rubric_bands)
      remove_column :completion_kit_prompts, :rubric_bands
    end
    if column_exists?(:completion_kit_prompts, :metric_group_id)
      remove_column :completion_kit_prompts, :metric_group_id
    end

    if column_exists?(:completion_kit_test_runs, :csv_data)
      remove_column :completion_kit_test_runs, :csv_data
    end
    if column_exists?(:completion_kit_test_runs, :description)
      remove_column :completion_kit_test_runs, :description
    end
    if column_exists?(:completion_kit_test_runs, :source)
      remove_column :completion_kit_test_runs, :source
    end
    if column_exists?(:completion_kit_test_runs, :eval_name)
      remove_column :completion_kit_test_runs, :eval_name
    end

    execute "UPDATE completion_kit_test_runs SET status = 'pending' WHERE status = 'draft'"
    execute "UPDATE completion_kit_test_runs SET status = 'completed' WHERE status = 'evaluated'"

    rename_table :completion_kit_test_runs, :completion_kit_runs
    rename_table :completion_kit_test_results, :completion_kit_responses
    rename_table :completion_kit_test_result_metric_assessments, :completion_kit_reviews
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
