class AddStatusAndErrorToResponses < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_responses, :status, :string, default: "pending", null: false
    add_column :completion_kit_responses, :error_provider, :string
    add_column :completion_kit_responses, :error_class, :string
    add_column :completion_kit_responses, :error_status, :integer
    add_column :completion_kit_responses, :error_message, :text
    add_column :completion_kit_responses, :attempts, :integer, default: 0, null: false
    add_column :completion_kit_responses, :row_index, :integer

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE completion_kit_responses
          SET status = 'succeeded'
          WHERE response_text IS NOT NULL AND length(response_text) > 0
        SQL
      end
    end
  end
end
