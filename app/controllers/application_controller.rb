# =============================================================================
# APPLICATION CONTROLLER
# =============================================================================
# This is the base class for all other controllers.
# Any method defined here is available in every controller.
# =============================================================================

class ApplicationController < ActionController::Base
  # This app has no per-user accounts — it's a single-user tool meant to run
  # on your LAN. This is just a gate so it isn't wide open to anyone who can
  # reach the host; it does not protect the /cable WebSocket endpoint, which
  # doesn't route through here.
  http_basic_authenticate_with(
    name:     Rails.application.credentials.dig(:auth, :username),
    password: Rails.application.credentials.dig(:auth, :password)
  )

  # Protects against Cross-Site Request Forgery attacks
  # Rails handles this automatically — just leave it here
  protect_from_forgery with: :exception

  # Make the current page title available in layouts
  # Usage in controller: @page_title = "Dashboard"
  helper_method :current_page_title

  private

  def current_page_title
    @page_title || "StorageFinder"
  end
end
