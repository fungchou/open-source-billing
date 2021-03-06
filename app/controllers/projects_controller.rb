class ProjectsController < ApplicationController

  helper_method :sort_column, :sort_direction

  layout :choose_layout
  include ProjectsHelper

  include DateFormats

  before_action :set_project, only: [:show, :edit, :update, :destroy]
  before_filter :authenticate_user!
  protect_from_forgery


  # GET /projects
  def index
    params[:status] = params[:status] || 'active'
    @projects = Project.joins("LEFT OUTER JOIN clients ON clients.id = projects.client_id ").filter(params,@per_page).order("#{sort_column} #{sort_direction}")
    @projects = filter_by_company(@projects)
    respond_to do |format|
      format.html # index.html.erb
      format.js
    end
  end

  # GET /projects/1
  def show
  end

  # GET /projects/new
  def new
    @project = Project.new
    3.times { @project.project_tasks.build(); @project.team_members.build() }
  end

  # GET /projects/1/edit
  def edit
  end

  # POST /projects
  def create
    @project = Project.new(project_params)
    @project.company_id = get_company_id
    if @project.save
      redirect_to projects_path, notice: 'Project was successfully created.'
    else
      render :new
    end
  end

  # PATCH/PUT /projects/1
  def update
    if @project.update(project_params)
      redirect_to projects_path, notice: 'Project was successfully updated.'
    else
      render :edit
    end
  end

  # DELETE /projects/1
  def destroy
    @project.destroy
    redirect_to projects_url, notice: 'Project was successfully destroyed.'
  end

  def sort_column
    params[:sort] ||= 'created_at'
    Project.column_names.include?(params[:sort]) ? params[:sort] : 'clients.organization_name'
  end


  def sort_direction
    params[:direction] ||= 'desc'
    %w[asc desc].include?(params[:direction]) ? params[:direction] : 'asc'
  end

  def bulk_actions
    result = Services::ProjectService.perform_bulk_action(params.merge({current_user: current_user}))
    @projects = filter_by_company(result[:projects]).order("#{sort_column} #{sort_direction}")
    @project_has_deleted_clients = project_has_deleted_clients?(@projects)
    @message = get_intimation_message(result[:action_to_perform], result[:project_ids])
    @action = result[:action]
    respond_to { |format| format.js }
  end

  def undo_actions
    params[:archived] ? Project.recover_archived(params[:ids]) : Project.recover_deleted(params[:ids])
    @projects = Project.unarchived.page(params[:page]).per(session["#{controller_name}-per_page"])
    @projects = filter_by_company(@projects).order("#{sort_column} #{sort_direction}")
    respond_to { |format| format.js }
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_project
      @project = Project.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def project_params
      params.require(:project).permit(:project_name, :description, :client_id, :manager_id, :billing_method,
                                      :total_hours, :company_id,:project_tasks_attributes,:team_members_attributes,
                                      project_tasks_attributes:
                                      [
                                        :id, :task_id, :name, :description, :rate, :project_id, :_destroy
                                      ],
                                      team_members_attributes:
                                      [
                                        :id, :staff_id, :email, :name, :rate, :project_id, :_destroy
                                      ]
      )
    end

  def get_company_id
    session['current_company'] || current_user.current_company || current_user.first_company_id
  end

  def project_has_deleted_clients?(projects)
    project_with_deleted_clients = []
    projects.each do |project|
      if project.unscoped_client.deleted_at.present?
        project_with_deleted_clients << project.project_name
      end
    end
    project_with_deleted_clients
  end

    def get_intimation_message(action_key, invoice_ids)
    helper_methods = {archive: 'projects_archived', destroy: 'projects_deleted'}
    helper_method = helper_methods[action_key.to_sym]
    helper_method.present? ? send(helper_method, invoice_ids) : nil
  end

end
