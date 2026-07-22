# =============================================================================
# ALERT MESSAGE BUILDER
# =============================================================================
# Builds the message content for alert notifications in different formats.
#
# Lives in its own file (not alongside AlertDeliveryService, even though this
# directory is Zeitwerk-collapsed — see the "storagefinder.autoload_collapse"
# initializer in config/application.rb) because Zeitwerk only autoloads one
# constant per file, matched to the filename. AlertCheckerJob#send_alerts
# references AlertMessageBuilder before AlertDeliveryService, so if this
# class isn't independently autoloadable, that reference raises
# "uninitialized constant AlertMessageBuilder" the first time it runs in a
# fresh process — silently caught by AlertCheckerJob's own rescue, so no
# alert ever gets sent and nothing visibly errors.
# =============================================================================

class AlertMessageBuilder
  def self.build(rule, triggered_units)
    new(rule, triggered_units).build
  end

  def initialize(rule, triggered_units)
    @rule            = rule
    @triggered_units = triggered_units
  end

  def build
    {
      subject:   build_subject,
      text_body: build_text_body,
      html_body: build_html_body,
      sms_body:  build_sms_body
    }
  end

  private

  def build_subject
    count = @triggered_units.length
    case @rule.trigger_type
    when "price_drop"
      "Price drop detected — #{count} unit#{"s" if count != 1} dropped in price"
    when "price_threshold"
      "#{count} unit#{"s" if count != 1} below $#{@rule.threshold_price}"
    end
  end

  def build_text_body
    lines = [ "Alert rule: #{@rule.name}", "" ]

    @triggered_units.first(10).each do |item|
      unit     = item[:unit]
      facility = unit.facility

      lines << "#{facility.company} — #{facility.name}"
      lines << "  Address: #{facility.full_address}"
      lines << "  Size: #{unit.size}"
      lines << "  Price: #{unit.formatted_price}"

      if item[:previous_price]
        change = unit.best_price - item[:previous_price]
        lines << "  Previous price: $#{item[:previous_price]}"
        lines << "  Change: #{change >= 0 ? "+" : ""}$#{change.round(2)}"
      end

      lines << "  Book: #{unit.booking_url}"
      lines << ""
    end

    if @triggered_units.length > 10
      lines << "... and #{@triggered_units.length - 10} more units."
      lines << "Open StorageFinder dashboard for full results."
    end

    lines.join("\n")
  end

  def build_html_body
    # Simple HTML table format for email
    rows = @triggered_units.first(10).map do |item|
      unit     = item[:unit]
      facility = unit.facility
      change   = item[:previous_price] ? (unit.best_price - item[:previous_price]).round(2) : nil

      <<~HTML
        <tr>
          <td>#{facility.company}</td>
          <td>#{facility.name}</td>
          <td>#{unit.size}</td>
          <td>#{unit.formatted_price}</td>
          #{ change ? "<td>#{change >= 0 ? "+" : ""}$#{change}</td>" : "<td>—</td>" }
          <td><a href="#{unit.booking_url}">Book now</a></td>
        </tr>
      HTML
    end

    <<~HTML
      <html><body>
        <h2>StorageFinder Alert: #{build_subject}</h2>
        <p>Rule: <strong>#{@rule.name}</strong></p>
        <table border="1" cellpadding="5" style="border-collapse:collapse">
          <tr>
            <th>Company</th><th>Facility</th><th>Size</th>
            <th>Price</th><th>Change</th><th>Book</th>
          </tr>
          #{rows.join}
        </table>
        #{@triggered_units.length > 10 ? "<p>...and #{@triggered_units.length - 10} more units.</p>" : ""}
      </body></html>
    HTML
  end

  def build_sms_body
    # SMS must be very short
    unit     = @triggered_units.first[:unit]
    facility = unit.facility
    "StorageFinder: #{facility.company} #{unit.size} #{unit.formatted_price} at #{facility.city}. #{unit.booking_url}"
  end
end
