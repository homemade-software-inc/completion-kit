class CollapseRunStatusAndAddFailureSummary < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_runs, :failure_summary, :string

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE completion_kit_runs
          SET status = 'running'
          WHERE status IN ('generating', 'judging')
        SQL
      end
    end
  end
end
