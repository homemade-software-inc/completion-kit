class AddVersioningAndReviewFieldsToCompletionKitPrompts < ActiveRecord::Migration[7.1]
  class Prompt < ActiveRecord::Base
    self.table_name = "completion_kit_prompts"
  end

  def up
    add_column :completion_kit_prompts, :family_key, :string
    add_column :completion_kit_prompts, :version_number, :integer
    add_column :completion_kit_prompts, :current, :boolean, default: true, null: false
    add_column :completion_kit_prompts, :assessment_model, :string
    add_column :completion_kit_prompts, :review_guidance, :text
    add_column :completion_kit_prompts, :rubric_text, :text
    add_column :completion_kit_prompts, :published_at, :datetime

    Prompt.reset_column_information

    Prompt.find_each do |prompt|
      prompt.update_columns(
        family_key: SecureRandom.uuid,
        version_number: 1,
        current: true,
        assessment_model: prompt.llm_model.presence || "gpt-4.1",
        review_guidance: "",
        rubric_text: default_rubric_text,
        published_at: prompt.created_at || Time.current
      )
    end

    change_column_null :completion_kit_prompts, :family_key, false
    change_column_null :completion_kit_prompts, :version_number, false
    add_index :completion_kit_prompts, :family_key
    add_index :completion_kit_prompts, [:family_key, :version_number], unique: true, name: "idx_completion_kit_prompts_family_version"
    add_index :completion_kit_prompts, [:family_key, :current], name: "idx_completion_kit_prompts_family_current"
  end

  def down
    remove_index :completion_kit_prompts, name: "idx_completion_kit_prompts_family_current"
    remove_index :completion_kit_prompts, name: "idx_completion_kit_prompts_family_version"
    remove_index :completion_kit_prompts, :family_key
    remove_column :completion_kit_prompts, :published_at
    remove_column :completion_kit_prompts, :rubric_text
    remove_column :completion_kit_prompts, :review_guidance
    remove_column :completion_kit_prompts, :assessment_model
    remove_column :completion_kit_prompts, :current
    remove_column :completion_kit_prompts, :version_number
    remove_column :completion_kit_prompts, :family_key
  end

  private

  def default_rubric_text
    <<~RUBRIC.strip
      10 - The result is correct, complete, clear, and directly useful without edits.
      8-9 - The result is very good but misses a small detail, nuance, or bit of clarity.
      6-7 - The result is useful but has noticeable gaps, weak structure, or minor inaccuracies.
      4-5 - The result is partially relevant but incomplete, vague, or inconsistently follows instructions.
      2-3 - The result is poor, confused, or largely misses the task.
      1 - The result is irrelevant or unrelated to the prompt and input data.
    RUBRIC
  end
end
