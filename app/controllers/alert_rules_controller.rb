# =============================================================================
# ALERT RULES CONTROLLER
# =============================================================================
# CRUD for alert rules — create, view, edit, delete price alert rules.
# =============================================================================

class AlertRulesController < ApplicationController
  before_action :set_alert_rule, only: [ :show, :edit, :update, :destroy ]

  def index
    @alert_rules = AlertRule.all.order(:name)
    @page_title  = "Alert Rules — StorageFinder"
  end

  def show
    @page_title = "#{@alert_rule.name} — StorageFinder"
  end

  def new
    @alert_rule = AlertRule.new
    @page_title = "New Alert Rule — StorageFinder"
  end

  def create
    @alert_rule = AlertRule.new(alert_rule_params)

    if @alert_rule.save
      flash[:notice] = "Alert rule '#{@alert_rule.name}' created."
      redirect_to alert_rules_path
    else
      flash.now[:alert] = "Could not create alert rule: #{@alert_rule.errors.full_messages.join(", ")}"
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @page_title = "Edit #{@alert_rule.name} — StorageFinder"
  end

  def update
    if @alert_rule.update(alert_rule_params)
      flash[:notice] = "Alert rule updated."
      redirect_to alert_rules_path
    else
      flash.now[:alert] = "Could not update: #{@alert_rule.errors.full_messages.join(", ")}"
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @alert_rule.name
    @alert_rule.destroy
    flash[:notice] = "Alert rule '#{name}' deleted."
    redirect_to alert_rules_path
  end

  private

  def set_alert_rule
    @alert_rule = AlertRule.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "Alert rule not found."
    redirect_to alert_rules_path
  end

  def alert_rule_params
    params.require(:alert_rule).permit(
      :name, :trigger_type, :threshold_price,
      :unit_size_filter, :company_filter,
      :email_enabled, :email_address,
      :discord_enabled, :discord_webhook_url,
      :sms_enabled, :sms_phone_number,
      :active
    )
  end
end
