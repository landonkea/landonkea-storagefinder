# =============================================================================
# CRAWL PROGRESS CHANNEL
# =============================================================================
# This ActionCable channel pushes live progress messages to the dashboard
# during a crawl. The dashboard subscribes to this channel and displays
# log lines and status updates in real time without page refreshes.
#
# The CrawlJob broadcasts to this channel using:
#   ActionCable.server.broadcast("crawl_progress_#{crawl_run.id}", data)
# =============================================================================

class CrawlProgressChannel < ApplicationCable::Channel
  # Called when a browser connects to this channel
  def subscribed
    crawl_run_id = params[:crawl_run_id].to_i

    if crawl_run_id.zero?
      reject   # Refuse the subscription — no (valid) crawl ID provided
      return
    end

    # Check that this crawl run exists
    unless CrawlRun.exists?(crawl_run_id)
      reject   # Refuse — crawl run doesn't exist
      return
    end

    # Subscribe this connection to the stream for this specific crawl
    # Broadcasts to "crawl_progress_123" will be sent to this connection
    stream_from "crawl_progress_#{crawl_run_id}"

    Rails.logger.info("[CrawlProgressChannel] Client subscribed to crawl_progress_#{crawl_run_id}")
  end

  # Called when the browser disconnects (page close, refresh, etc.)
  def unsubscribed
    Rails.logger.debug("[CrawlProgressChannel] Client unsubscribed")
    stop_all_streams
  end
end
