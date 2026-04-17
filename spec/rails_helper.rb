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
require_relative "spec_helper"
require "completion_kit"

class CompletionKitSpecApp < Rails::Application
  config.root = DUMMY_APP_ROOT
  config.eager_load = false
  config.hosts << "www.example.com"
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
  create_table :completion_kit_criteria, force: true do |t|
    t.string :name
    t.text :description
    t.timestamps
  end

  create_table :completion_kit_metrics, force: true do |t|
    t.string :name
    t.text :instruction
    t.text :rubric_bands
    t.string :key
    t.timestamps
  end

  create_table :completion_kit_criteria_memberships, force: true do |t|
    t.references :criteria, null: false
    t.references :metric, null: false
    t.integer :position
    t.timestamps
  end

  create_table :completion_kit_provider_credentials, force: true do |t|
    t.string :provider
    t.text :api_key
    t.text :api_endpoint
    t.string :discovery_status
    t.integer :discovery_current, default: 0
    t.integer :discovery_total, default: 0
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
    t.references :prompt, null: false
    t.references :dataset
    t.string :judge_model
    t.string :status
    t.integer :progress_current, default: 0
    t.integer :progress_total, default: 0
    t.text :error_message
    t.float :temperature, default: 1.0
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
    t.timestamps
  end

  create_table :completion_kit_reviews, force: true do |t|
    t.references :response, null: false
    t.references :metric
    t.string :metric_name
    t.text :instruction
    t.string :status
    t.decimal :ai_score, precision: 4, scale: 1
    t.text :ai_feedback
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
    t.timestamps
  end
end

FactoryBot.definition_file_paths = [File.expand_path("factories", __dir__)]
FactoryBot.find_definitions

RSpec.configure do |config|
  config.fixture_paths = ["#{::Rails.root}/spec/fixtures"]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods
end
