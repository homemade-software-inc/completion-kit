ENV["RAILS_ENV"] ||= "test"

DUMMY_APP_ROOT ||= File.expand_path("dummy", __dir__)

require "bundler/setup"
require "logger"
require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "active_record/railtie"
require "active_job/railtie"
require "action_mailer/railtie"
require "action_cable/engine"
require "sprockets/railtie"
require "rspec/rails"
require "factory_bot_rails"
require "solid_queue"
require_relative "spec_helper"
require "completion_kit"

class CompletionKitSpecApp < Rails::Application
  config.root = DUMMY_APP_ROOT
  config.eager_load = false
  config.hosts << "www.example.com"
  config.cache_store = :memory_store
  config.logger = Logger.new(nil)
  config.secret_key_base = "completion-kit-test-key"
  config.active_support.cache_format_version = 7.1
  config.assets.unknown_asset_fallback = true
  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = :none
  config.paths["config/routes.rb"] = File.join(DUMMY_APP_ROOT, "config/routes.rb")
  config.active_record.encryption.primary_key = "test-primary-key-must-be-32-char"
  config.active_record.encryption.deterministic_key = "test-deterministic-key-32-chars!"
  config.active_record.encryption.key_derivation_salt = "test-key-derivation-salt-32-char"
end

Rails.application ||= CompletionKitSpecApp.instance
CompletionKitSpecApp.initialize! unless Rails.application.initialized?

Rails.application.routes.draw do
  mount CompletionKit::Engine => "/completion_kit"
end

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false

ActiveRecord::Schema.define do
  create_table :completion_kit_metric_groups, force: true do |t|
    t.string :name
    t.text :description
    t.timestamps
  end

  create_table :completion_kit_metrics, force: true do |t|
    t.string :name
    t.text :instruction
    t.text :rubric_bands
    t.string :key
    t.string :metric_type, null: false, default: "llm_judge"
    t.text :check_config
    t.timestamps
  end

  create_table :completion_kit_metric_group_memberships, force: true do |t|
    t.references :metric_group, null: false
    t.references :metric, null: false
    t.integer :position
    t.timestamps
  end

  create_table :completion_kit_provider_credentials, force: true do |t|
    t.string :provider
    t.text :api_key
    t.text :api_endpoint
    t.string :api_version
    t.string :discovery_status
    t.integer :discovery_current, default: 0
    t.integer :discovery_total, default: 0
    t.text :discovery_error
    t.integer :catalog_model_count
    t.timestamps
  end

  create_table :completion_kit_datasets, force: true do |t|
    t.string :name, null: false
    t.text :csv_data, null: false
    t.timestamps
  end

  create_table :completion_kit_prompts, force: true do |t|
    t.string :name
    t.text :description
    t.text :template
    t.string :llm_model
    t.string :family_key
    t.integer :version_number
    t.boolean :current, default: true, null: false
    t.datetime :published_at
    t.timestamps
  end

  create_table :completion_kit_runs, force: true do |t|
    t.string :name
    t.references :prompt
    t.references :dataset
    t.string :judge_model
    t.string :status
    t.integer :progress_current, default: 0
    t.integer :progress_total, default: 0
    t.text :error_message
    t.text :failure_summary
    t.float :temperature, default: 1.0
    t.boolean :temperature_ignored, default: false, null: false
    t.string :output_column
    t.string :expected_column
    t.timestamps
  end

  create_table :completion_kit_run_metrics, force: true do |t|
    t.references :run, null: false
    t.references :metric, null: false
    t.integer :position
    t.timestamps
  end

  create_table :completion_kit_responses, force: true do |t|
    t.references :run, null: false
    t.text :input_data
    t.text :response_text
    t.text :expected_output
    t.string :status, default: "pending", null: false
    t.string :error_provider
    t.string :error_class
    t.integer :error_status
    t.text :error_message
    t.integer :attempts, default: 0, null: false
    t.integer :row_index
    t.index [:run_id, :status]
    t.timestamps
  end

  create_table :completion_kit_reviews, force: true do |t|
    t.references :response, null: false
    t.references :metric
    t.bigint :metric_version_id
    t.string :metric_name
    t.text :instruction
    t.string :status
    t.decimal :ai_score, precision: 4, scale: 1
    t.boolean :passed
    t.text :ai_feedback
    t.string :error_provider
    t.string :error_class
    t.integer :error_status
    t.text :error_message
    t.integer :attempts, default: 0, null: false
    t.index [:response_id, :status]
    t.index :metric_version_id, name: "index_ck_reviews_on_metric_version_id"
    t.timestamps
  end

  create_table :completion_kit_models, force: true do |t|
    t.string :provider, null: false
    t.string :model_id, null: false
    t.string :display_name
    t.string :status, null: false
    t.boolean :supports_generation
    t.boolean :supports_judging
    t.text :generation_error
    t.text :judging_error
    t.datetime :probed_at
    t.datetime :discovered_at
    t.datetime :retired_at
    t.timestamps
  end

  create_table :completion_kit_suggestions, force: true do |t|
    t.references :run, null: false
    t.references :prompt, null: false
    t.text :reasoning
    t.text :suggested_template
    t.text :original_template
    t.datetime :applied_at
    t.text :validation_summary
    t.string :status, default: "ready", null: false
    t.timestamps
  end

  create_table :solid_queue_processes, force: true do |t|
    t.string :kind, null: false
    t.datetime :last_heartbeat_at, null: false
    t.bigint :supervisor_id
    t.integer :pid, null: false
    t.string :hostname
    t.text :metadata
    t.datetime :created_at, null: false
    t.string :name, null: false
  end

  create_table :completion_kit_tags, force: true do |t|
    t.string :name, null: false
    t.string :color, null: false
    t.timestamps
  end
  add_index :completion_kit_tags, :name, unique: true

  create_table :completion_kit_taggings, force: true do |t|
    t.references :tag, null: false
    t.string :taggable_type, null: false
    t.bigint :taggable_id, null: false
    t.timestamps
  end
  add_index :completion_kit_taggings, [:taggable_type, :taggable_id]
  add_index :completion_kit_taggings,
            [:tag_id, :taggable_type, :taggable_id],
            unique: true,
            name: "idx_taggings_unique"

  create_table :completion_kit_mcp_sessions, force: true do |t|
    t.string :session_id, null: false
    t.datetime :expires_at, null: false
    t.timestamps
  end
  add_index :completion_kit_mcp_sessions, :session_id, unique: true
  add_index :completion_kit_mcp_sessions, :expires_at

  create_table :completion_kit_dashboard_dismissals, force: true do |t|
    t.string :dismissable_type, null: false
    t.bigint :dismissable_id, null: false
    t.decimal :baseline_score, precision: 4, scale: 1
    t.timestamps
  end
  add_index :completion_kit_dashboard_dismissals,
            [:dismissable_type, :dismissable_id],
            unique: true,
            name: "index_ck_dashboard_dismissals_on_dismissable"

  create_table :completion_kit_metric_versions, force: true do |t|
    t.references :metric, null: false
    t.text :instruction
    t.text :rubric_bands
    t.boolean :current, null: false, default: true
    t.string :state, null: false, default: "published"
    t.string :source
    t.integer :version_number
    t.datetime :published_at
    t.text :validation_summary
    t.string :metric_type, null: false, default: "llm_judge"
    t.text :check_config
    t.timestamps
  end
  add_index :completion_kit_metric_versions, [:metric_id, :current], name: "index_ck_metric_versions_on_metric_current"
  add_index :completion_kit_metric_versions, [:metric_id, :state], name: "index_ck_metric_versions_on_metric_state"
  add_index :completion_kit_metric_versions, [:metric_id, :version_number], name: "index_ck_metric_versions_on_metric_vnum"

  create_table :completion_kit_agreements, force: true do |t|
    t.references :run, null: false
    t.references :response, null: false
    t.references :metric, null: false
    t.references :metric_version, null: false
    t.string :verdict, null: false
    t.string :created_by
    t.decimal :corrected_score, precision: 4, scale: 1
    t.text :note
    t.boolean :excluded_from_examples, null: false, default: false
    t.timestamps
  end
  add_index :completion_kit_agreements,
            [:response_id, :metric_id, :created_by],
            unique: true,
            name: "index_ck_agreements_on_response_metric_user"

  create_table :completion_kit_starter_metric_dismissals, force: true do |t|
    t.string :starter_key, null: false
    t.timestamps
  end
  add_index :completion_kit_starter_metric_dismissals, :starter_key,
            unique: true,
            name: "index_ck_starter_dismissals_on_key"
end

FactoryBot.definition_file_paths = [File.expand_path("factories", __dir__)]
FactoryBot.find_definitions

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.fixture_paths = ["#{::Rails.root}/spec/fixtures"]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods
  config.before { Rails.cache.clear }
  config.before { CompletionKit.config.judge_agreement_enabled = true }
  config.before { CompletionKit.config.on_run_created = nil }
  config.before { CompletionKit.config.on_run_started = nil }
  config.before do
    server = ActionCable.server
    adapter = ActionCable::SubscriptionAdapter::Test.new(server)
    server.instance_variable_set(:@pubsub, adapter)
  end
end
