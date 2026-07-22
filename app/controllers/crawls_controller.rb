# =============================================================================
# CRAWLS CONTROLLER
# =============================================================================
# Handles starting, viewing, and managing crawl runs.
# =============================================================================

class CrawlsController < ApplicationController
  # ---------------------------------------------------------------------------
  # CREATE — start a new crawl (called when user clicks "Run Crawl")
  # ---------------------------------------------------------------------------
  def create
    # Refuse to start a new crawl if one is already running
    if CrawlRun.any_running?
      respond_to do |format|
        format.html {
          flash[:alert] = "A crawl is already running. Please wait for it to finish before starting a new one."
          redirect_to root_path
        }
        format.json { render json: { error: "A crawl is already running" }, status: :conflict }
      end
      return
    end

    # Validate that we have a search city
    search_city = params[:search_city]&.strip
    if search_city.blank?
      respond_to do |format|
        format.html {
          flash[:alert] = "Please enter a city name or ZIP code to search."
          redirect_to root_path
        }
        format.json { render json: { error: "Search city is required" }, status: :unprocessable_entity }
      end
      return
    end

    # Validate the radius
    radius = params[:radius_miles].to_i
    if radius <= 0 || radius > 500
      respond_to do |format|
        format.html {
          flash[:alert] = "Radius must be between 1 and 500 miles."
          redirect_to root_path
        }
        format.json { render json: { error: "Invalid radius" }, status: :unprocessable_entity }
      end
      return
    end

    # Build filter options from form params.
    # sizes[] and companies[] are real checkbox arrays (see dashboard/index.html.erb),
    # not comma-separated strings.
    options = {
      sizes:             Array(params[:sizes]).presence || Unit::DEFAULT_SIZES,
      climate_controlled: params[:climate_only] != "false",
      companies:         Array(params[:companies]).presence,
      exclude_types:     Unit::EXCLUDED_TYPES
    }

    # Create the CrawlRun record
    crawl_run = CrawlRun.create!(
      search_city:          search_city,
      search_radius_miles:  radius,
      status:               "pending",
      filter_options:       options,
      companies_included:   options[:companies] || CompanyRegistry.all_company_names
    )

    Rails.logger.info("[CrawlsController] Created CrawlRun ##{crawl_run.id} for '#{search_city}' within #{radius} miles")

    # Enqueue the background job — this returns immediately, job runs in background
    CrawlJob.perform_later(crawl_run_id: crawl_run.id, options: options)

    Rails.logger.info("[CrawlsController] CrawlJob enqueued for CrawlRun ##{crawl_run.id}")

    respond_to do |format|
      format.html {
        flash[:notice] = "Crawl started for '#{search_city}' within #{radius} miles. Results will appear below as they come in."
        redirect_to root_path
      }
      format.json {
        render json: {
          crawl_run_id: crawl_run.id,
          message:      "Crawl started",
          status:       "pending"
        }, status: :created
      }
    end

  rescue ActiveRecord::RecordInvalid => e
    # The CrawlRun record failed validation — shouldn't happen with our checks above,
    # but handle it gracefully just in case
    Rails.logger.error("[CrawlsController] Failed to create CrawlRun: #{e.message}")
    respond_to do |format|
      format.html {
        flash[:alert] = "Could not start crawl: #{e.message}"
        redirect_to root_path
      }
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  # ---------------------------------------------------------------------------
  # SHOW — detail page for one crawl run (shows log entries)
  # ---------------------------------------------------------------------------
  def show
    @crawl_run = CrawlRun.find(params[:id])
    @log_entries = @crawl_run.crawl_log_entries.order(:created_at)
    @page_title = "Crawl ##{@crawl_run.id} — StorageFinder"

  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "Crawl run ##{params[:id]} not found."
    redirect_to root_path
  end

  # ---------------------------------------------------------------------------
  # LOG — JSON endpoint that returns log entries for a running crawl
  # Used by the live progress feed on the dashboard
  # ---------------------------------------------------------------------------
  def log
    crawl_run   = CrawlRun.find(params[:id])
    since_id    = params[:since_id].to_i  # Only return entries newer than this ID

    entries = crawl_run.crawl_log_entries
                       .where("id > ?", since_id)
                       .order(:created_at)

    render json: {
      entries: entries.map { |e|
        {
          id:        e.id,
          level:     e.level,
          company:   e.company,
          message:   e.message,
          timestamp: e.created_at.strftime("%H:%M:%S"),
          css_class: e.css_class
        }
      },
      crawl_status: crawl_run.status,
      finished:     crawl_run.finished?
    }

  rescue ActiveRecord::RecordNotFound
    render json: { error: "Crawl run not found" }, status: :not_found
  end

  # ---------------------------------------------------------------------------
  # DESTROY — cancel a running crawl (marks it as failed), or permanently
  # delete the record (and its units/log entries) once it's finished
  # ---------------------------------------------------------------------------
  def destroy
    crawl_run = CrawlRun.find(params[:id])

    if crawl_run.finished?
      crawl_run.destroy!

      respond_to do |format|
        format.html {
          flash[:notice] = "Crawl record deleted."
          redirect_to root_path
        }
        format.json { render json: { message: "Crawl deleted" } }
      end
    else
      crawl_run.fail!("Cancelled by user at #{Time.current.strftime("%I:%M %p")}")

      respond_to do |format|
        format.html {
          flash[:notice] = "Crawl cancelled."
          redirect_to root_path
        }
        format.json { render json: { message: "Crawl cancelled", status: "failed" } }
      end
    end

  rescue ActiveRecord::RecordNotFound
    render json: { error: "Crawl run not found" }, status: :not_found
  end

  # ---------------------------------------------------------------------------
  # DESTROY_SELECTED — bulk-delete crawl history records
  # Used by the "select all" / "Delete Selected" controls in the history panel.
  # Only finished crawls (completed/failed) are deleted — a still-running or
  # pending crawl is skipped rather than deleted out from under its job.
  # ---------------------------------------------------------------------------
  def destroy_selected
    ids = Array(params[:ids]).map(&:to_i).reject(&:zero?)

    if ids.empty?
      respond_to do |format|
        format.html {
          flash[:alert] = "No crawl records were selected."
          redirect_to root_path
        }
        format.json { render json: { error: "No ids given" }, status: :unprocessable_entity }
      end
      return
    end

    crawl_runs    = CrawlRun.where(id: ids)
    deletable_ids = crawl_runs.select(&:finished?).map(&:id)
    skipped_count = crawl_runs.size - deletable_ids.size

    deleted_count = deletable_ids.size
    CrawlRun.where(id: deletable_ids).destroy_all

    message = "Deleted #{deleted_count} crawl record#{"s" unless deleted_count == 1}."
    if skipped_count > 0
      message += " Skipped #{skipped_count} still-running crawl#{"s" unless skipped_count == 1} — cancel #{skipped_count == 1 ? "it" : "them"} first to delete."
    end

    respond_to do |format|
      format.html {
        flash[:notice] = message
        redirect_to root_path
      }
      format.json { render json: { message: message, deleted: deleted_count, skipped: skipped_count } }
    end
  end
end
