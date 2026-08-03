# A Rails "helper" module holds plain Ruby methods meant to be called from
# view templates (.erb files) to keep view logic out of the HTML markup —
# e.g. formatting a date or building a CSS class string. `module` (rather
# than `class`) defines a namespace of methods that isn't meant to be
# instantiated (you never write `ApplicationHelper.new`) — Rails
# automatically makes every public method defined in here available inside
# every view template, app-wide, without any extra setup.
#
# `ApplicationHelper` is the default, catch-all helper module Rails
# generates for every new app — by convention every controller also gets
# its own matching helper module (e.g. DashboardHelper for
# DashboardController), but none of those exist yet in this app.
module ApplicationHelper
  # Reads one count out of the `@crawl_log_counts` Hash DashboardController#index
  # builds (see that method's own comment for why it's built as one grouped
  # query up front instead of querying per-row here). `crawl_run_id:` and
  # `level:` (either "warning" or "error") together form the Hash's key —
  # `.fetch([crawl_run_id, level], 0)` looks that pair up and returns 0
  # instead of `nil` when there were no matching log entries, so callers in
  # the view (see app/views/dashboard/_crawl_history.html.erb) never have to
  # guard against a `nil` count themselves.
  def crawl_log_issue_count(crawl_run_id:, level:)
    (@crawl_log_counts || {}).fetch([ crawl_run_id, level ], 0)
  end
end
# `end` closes the `module ApplicationHelper` block opened above. The module
# body is empty — no shared helper methods have been added yet, but the file
# still needs to exist because Rails' default configuration expects/loads it.
