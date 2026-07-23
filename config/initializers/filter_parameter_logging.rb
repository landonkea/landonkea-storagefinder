# A reminder that, like every file in config/initializers/, this one only
# takes effect at application boot — editing it has no effect on an
# already-running server until it is stopped and restarted. (See
# config/initializers/assets.rb for a full explanation of what an
# "initializer" is and why Rails auto-loads everything in this directory.)
# Be sure to restart your server when you modify this file.

# Blank line — purely visual spacing, has no effect on Ruby.

# Explains what the code below does at a high level: Rails logs every
# incoming request's parameters (form fields, query-string values, etc.) to
# the log file for debugging purposes. Some of those parameters are
# sensitive (passwords, tokens, etc.) and should never appear in plain text
# in a log file, which might be readable by more people than the actual
# data should be. "Partially matched" means the filter doesn't need the
# exact parameter name — a filter for `passw` also catches `password`,
# `password_confirmation`, `old_passwd`, and so on, because it matches
# anywhere the substring appears.
# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.

# `Rails.application.config` is the app's configuration object (see
# assets.rb for what `Rails.application` means). `.filter_parameters` is
# the specific setting being modified here — Rails already ships with a
# small default list of filtered parameter names (like "password" itself);
# `+=` is Ruby's "add-and-reassign" shorthand: it's equivalent to writing
# `filter_parameters = filter_parameters + [...]`, meaning it takes the
# existing list, concatenates the new Array of names supplied below onto
# the end of it, and reassigns the result back to `filter_parameters` —
# so this ADDS to the defaults rather than replacing them. The opening
# square bracket `[` below starts a multi-line Array literal (an ordered
# list of values); Ruby allows an array literal's items to span several
# lines as long as the brackets eventually balance.
Rails.application.config.filter_parameters += [
  # Each of these is a Ruby Symbol — a lightweight, immutable, named value
  # written with a leading colon (`:name`), commonly used instead of a
  # plain string for fixed/identifier-like values such as these parameter-
  # name patterns. Every symbol below is one substring pattern; any request
  # parameter whose name CONTAINS that substring (case-insensitively, per
  # ActiveSupport::ParameterFilter's default matching) gets its value
  # replaced with "[FILTERED]" in the logs instead of the real value:
  #   :passw       -> matches "password", "passwd", etc.
  #   :email       -> matches "email", "user_email", etc.
  #   :secret      -> matches "secret", "client_secret", etc.
  #   :token       -> matches "token", "auth_token", "csrf_token", etc.
  #   :_key        -> matches "api_key", "secret_key", etc. (leading
  #                   underscore means it only matches when "key" is
  #                   preceded by another word-part, not the bare word
  #                   "key" alone)
  #   :crypt       -> matches "encrypted_password", "crypted_foo", etc.
  #   :salt        -> matches "password_salt", etc.
  #   :certificate -> matches "certificate", "ssl_certificate", etc.
  #   :otp         -> matches "otp", "otp_secret" (one-time password codes)
  #   :ssn         -> matches "ssn" (US Social Security Number)
  #   :cvv         -> matches "cvv" (credit card verification value)
  #   :cvc         -> matches "cvc" (credit card verification code — an
  #                   alternate name some payment processors use for the
  #                   same 3/4-digit security code as CVV)
  # This whole line is one Array literal's contents, with each symbol
  # separated by a comma — Ruby doesn't care that it's all on one line vs.
  # one-per-line, both are valid, this is simply the style chosen here.
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]
# This closing square bracket `]` ends the Array literal that was opened on
# the `+=` line above, and with it, the full statement that reassigns
# `Rails.application.config.filter_parameters`.
