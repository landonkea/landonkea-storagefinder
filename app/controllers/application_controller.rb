# =============================================================================
# APPLICATION CONTROLLER
# =============================================================================
# This is the base class for all other controllers.
# Any method defined here is available in every controller.
# =============================================================================

# A Rails "controller" is a class whose methods (called "actions") handle
# incoming web requests — e.g. a visitor loading a page, or a browser
# submitting a form. Rails matches an incoming URL to a specific
# controller + action (that routing is configured in config/routes.rb, not
# here), runs that action's Ruby code, and sends back a response (usually
# an HTML page or some JSON data).
#
# `class ApplicationController < ActionController::Base` makes this class
# inherit from (be built on top of) Rails' `ActionController::Base`, which
# provides all the underlying request/response machinery. Every OTHER
# controller in this app (AlertRulesController, CrawlsController, etc.) in
# turn inherits from THIS class, so anything defined here — settings,
# helper methods, before_action hooks — automatically applies to all of them.
class ApplicationController < ActionController::Base
  # This app has no per-user accounts — it's a single-user tool meant to run
  # on your LAN. This is just a gate so it isn't wide open to anyone who can
  # reach the host; it does not protect the /cable WebSocket endpoint, which
  # doesn't route through here.
  # `http_basic_authenticate_with` is a Rails class method that wraps EVERY
  # action in EVERY controller inheriting from this one behind HTTP Basic
  # Auth — the browser's native username/password popup, not a custom login
  # page. It's called here with a hash of two keyword arguments: `name:` and
  # `password:`.
  http_basic_authenticate_with(
    # `Rails.application.credentials` is Rails' encrypted secrets store
    # (backed by config/credentials.yml.enc, which is excluded from this
    # comment pass since it's encrypted ciphertext). `.dig(:auth, :username)`
    # looks up credentials[:auth][:username] — `.dig` safely walks nested
    # keys and returns nil if any level along the way is missing, instead of
    # raising an error the way credentials[:auth][:username] directly could
    # if :auth weren't present. `:auth` and `:username` are Ruby symbols —
    # lightweight, immutable names (similar to strings, but more efficient
    # and conventionally used as hash keys/identifiers rather than text).
    name:     Rails.application.credentials.dig(:auth, :username),
    # Same `.dig` lookup, this time for the configured password.
    password: Rails.application.credentials.dig(:auth, :password)
  )
  # (No `end` needed here — this is a single method call spanning multiple
  # lines via the parentheses, not a `do...end` or `if...end` block.)

  # Protects against Cross-Site Request Forgery attacks
  # Rails handles this automatically — just leave it here
  # `protect_from_forgery` is a class method enabling Rails' built-in CSRF
  # protection: it requires a hidden, per-session security token on every
  # form submission (POST/PATCH/DELETE requests) to prove the request really
  # came from this app's own pages, not a malicious third-party site tricking
  # a logged-in browser into submitting a request. `with: :exception` is a
  # keyword argument telling Rails WHAT to do if that token is missing or
  # wrong: raise an exception (which halts the request with an error) rather
  # than silently clearing the user's session (the other built-in option).
  protect_from_forgery with: :exception

  # Make the current page title available in layouts
  # Usage in controller: @page_title = "Dashboard"
  # `helper_method` is a Rails class method that takes the name of a PRIVATE
  # controller method (as a symbol, `:current_page_title`) and makes it
  # additionally callable from view templates (.erb files), which normally
  # can't see private controller methods at all. This lets every page's
  # layout call `current_page_title` to render a <title> tag.
  helper_method :current_page_title

  # `private` is a Ruby keyword (not a method call on an object) that marks
  # every method defined BELOW this point in the class as private — meaning
  # it can only be called from inside this class (or a subclass) without
  # explicitly naming an object to call it on. It prevents external code
  # (like a route or a view, without going through `helper_method` above)
  # from calling `current_page_title` directly on a controller instance.
  private

  # `def current_page_title` defines the private helper method referenced by
  # `helper_method :current_page_title` above. No arguments are needed —
  # empty parentheses are omitted, which Ruby allows.
  def current_page_title
    # `@page_title` is an instance variable — a piece of data that an
    # individual controller action can set (e.g. `@page_title = "Dashboard —
    # StorageFinder"` in DashboardController#index) and which is
    # automatically visible to both this method and the view template that
    # renders after it, without needing to pass it around explicitly. `||`
    # is Ruby's "or" operator here used as a fallback: if @page_title was
    # never set (so it's `nil`, which counts as falsy in Ruby), the
    # expression evaluates to the string on the right instead. This is the
    # method's return value, since it's the only/last expression evaluated.
    @page_title || "StorageFinder"
  end
  # `end` closes the `def current_page_title` method definition opened above.
end
# `end` closes the `class ApplicationController` definition opened at the
# top of the file.
