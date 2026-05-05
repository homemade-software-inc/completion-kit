class JobsDashboardConstraint
  def self.matches?(request)
    cfg = CompletionKit.config
    return true unless cfg.username && cfg.password
    request.session[:authenticated]
  end
end
