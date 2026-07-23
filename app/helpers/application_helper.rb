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
end
# `end` closes the `module ApplicationHelper` block opened above. The module
# body is empty — no shared helper methods have been added yet, but the file
# still needs to exist because Rails' default configuration expects/loads it.
