# =============================================================================
# API KEYS CONTROLLER
# =============================================================================
# Admin-only management of ApiKey records (see app/models/api_key.rb). This
# controller inherits from ApplicationController, so — unlike the
# Api::V1::* controllers it manages keys for — it sits behind the same HTTP
# Basic Auth as the rest of the dashboard. Only the site owner can issue or
# revoke API keys; the keys themselves are what external tools then use to
# reach /api/v1 without that Basic Auth password.
# =============================================================================

class ApiKeysController < ApplicationController
  before_action :set_api_key, only: [ :destroy, :regenerate ]

  def index
    @api_keys = ApiKey.order(created_at: :desc)
    @api_key = ApiKey.new
  end

  def create
    @api_key = ApiKey.new(api_key_params)

    if @api_key.save
      # `flash[:new_token]` (rather than the usual :notice) carries the raw
      # token through the redirect for one-time display only — after this
      # page render, only the masked form is ever shown again.
      flash[:new_token] = @api_key.token
      redirect_to api_keys_path, notice: "API key \"#{@api_key.name}\" created."
    else
      @api_keys = ApiKey.order(created_at: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @api_key.destroy
    redirect_to api_keys_path, notice: "API key \"#{@api_key.name}\" revoked and deleted."
  end

  def regenerate
    @api_key.regenerate_token
    flash[:new_token] = @api_key.token
    redirect_to api_keys_path, notice: "API key \"#{@api_key.name}\" regenerated. Update any integrations using it."
  end

  private

  def set_api_key
    @api_key = ApiKey.find(params[:id])
  end

  def api_key_params
    params.require(:api_key).permit(:name)
  end
end
