# A "mailer" is Rails' framework for building and sending emails — you
# define one method per kind of email (e.g. "send_alert"), and each method
# renders an .erb template into an email body instead of an HTML page.
# `class ApplicationMailer < ActionMailer::Base` makes this the base class
# every other mailer in the app inherits from (is built on top of); it
# provides Rails' `ActionMailer::Base` machinery (the `mail` method,
# template rendering, delivery, etc.) to every mailer that extends this one.
class ApplicationMailer < ActionMailer::Base
  # Sets the default "From:" address for every email sent by any mailer that
  # inherits from this class, unless that mailer/method overrides it.
  # `default` is a class method (called here with no explicit receiver,
  # meaning it runs on ApplicationMailer itself) that takes a hash of
  # fallback values — `from:` is a hash key (using Ruby's shorthand `key:
  # value` syntax) that ActionMailer recognizes as "put this in the From
  # header of every outgoing message."
  # FLAG: "from@example.com" looks like a placeholder that was never
  # replaced with a real sending address — see the end-of-task report for
  # a note on this (not fixed here, per the comments-only instructions).
  default from: "from@example.com"

  # Tells ActionMailer to wrap every email's rendered content in the shared
  # HTML/text template found at app/views/layouts/mailer.html.erb (and
  # mailer.text.erb, if present) — the same idea as a Rails page layout, but
  # for emails. `layout "mailer"` is a class method call; the string
  # "mailer" is the layout's filename (without the .html.erb/.text.erb
  # extension).
  layout "mailer"
end
# `end` closes the `class ApplicationMailer` definition opened above.
