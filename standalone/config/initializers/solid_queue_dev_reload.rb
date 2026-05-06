if Rails.env.development?
  Rails.application.config.after_initialize do
    SolidQueue.app_executor = Rails.application.reloader
  end
end
