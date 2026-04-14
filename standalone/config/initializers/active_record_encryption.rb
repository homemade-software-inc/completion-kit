Rails.application.config.active_record.encryption.primary_key =
  ENV["COMPLETION_KIT_ENCRYPTION_PRIMARY_KEY"] || "development-primary-key-32-chars!"

Rails.application.config.active_record.encryption.deterministic_key =
  ENV["COMPLETION_KIT_ENCRYPTION_DETERMINISTIC_KEY"] || "development-deterministic-key-32"

Rails.application.config.active_record.encryption.key_derivation_salt =
  ENV["COMPLETION_KIT_ENCRYPTION_KEY_DERIVATION_SALT"] || "development-key-derivation-salt3"

if Rails.env.production? &&
    [ENV["COMPLETION_KIT_ENCRYPTION_PRIMARY_KEY"],
     ENV["COMPLETION_KIT_ENCRYPTION_DETERMINISTIC_KEY"],
     ENV["COMPLETION_KIT_ENCRYPTION_KEY_DERIVATION_SALT"]].any?(&:nil?)
  raise "CompletionKit encryption keys must be set via COMPLETION_KIT_ENCRYPTION_* env vars in production. " \
        "Generate them with: bin/rails db:encryption:init"
end
