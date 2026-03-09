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
    t.text :description
    t.text :guidance_text
    t.text :rubric_text
    t.text :rubric_bands
    t.string :key
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
    t.string :assessment_model
    t.text :review_guidance
    t.text :rubric_text
    t.text :rubric_bands
    t.datetime :published_at
    t.references :metric_group
    t.timestamps
  end

  create_table :completion_kit_test_runs, force: true do |t|
    t.string :name
    t.text :description
    t.references :prompt, null: false
    t.text :csv_data
    t.string :status
    t.string :source, default: "ui"
    t.string :eval_name
    t.timestamps
  end

  create_table :completion_kit_test_results, force: true do |t|
    t.references :test_run, null: false
    t.string :status
    t.text :input_data
    t.text :output_text
    t.text :expected_output
    t.text :judge_feedback
    t.decimal :quality_score, precision: 5, scale: 2
    t.decimal :human_score, precision: 4, scale: 1
    t.text :human_feedback
    t.string :human_reviewer_name
    t.datetime :human_reviewed_at
    t.timestamps
  end

  create_table :completion_kit_test_result_metric_assessments, force: true do |t|
    t.references :test_result, null: false
    t.references :metric
    t.string :metric_name
    t.text :guidance_text
    t.text :rubric_text
    t.string :status
    t.decimal :ai_score, precision: 4, scale: 1
    t.text :ai_feedback
    t.decimal :human_score, precision: 4, scale: 1
    t.text :human_feedback
    t.string :human_reviewer_name
    t.datetime :human_reviewed_at
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
