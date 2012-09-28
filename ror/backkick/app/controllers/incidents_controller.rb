class IncidentsController < ApplicationController

  skip_before_filter :authorize, only: [:new,
                                        :create,
                                        :show,
                                        :search,
                                        :total_given,
                                        :thank_you]
  
  PAGE_SIZE = 20
  
  INCLUDE_INCIDENT_JSON_DESC = {
    :include => {
      :public_entity => {
        :only => :name,
        :include => { :category => {
            :only => :name }
        }
      },
      :place => { :only => [:name, :latitude, :longitude] }
    }
  }
  
  # GET /incidents
  # GET /incidents.json
  def index
    @incidents = Incident.order("created_at desc")

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @incidents }
    end
  end

  # GET /incidents/search
  # GET /incidents/search.json
  def search
    @incidents = Incident.includes(:public_entity, :place,
                                   :public_entity => :category)
      .order("incidents.created_at desc")

    @approval_status = params[:approval_status]
    if session[:user_id] && @approval_status
      
      @incidents =
        @incidents.where(:approval_status => @approval_status)
    else
      @incidents =
        @incidents.where(:approval_status => Incident::APPROVED_STATUS)
    end
    
    @praise = params[:praise]
    
    if @praise == "true"
      @incidents = @incidents.where(:praise => true)
    elsif @praise == "false"
      @incidents = @incidents.where(:praise => false)
    end

    @category_id = params[:category_id]
    if @category_id != ""
      @incidents = @incidents.joins(:public_entity => :category)
        .where('category_id = ?', "#{params[:category_id]}")
    end

    @place_name_filter = params[:place_name_filter]
    if @place_name_filter != ""
      @incidents = @incidents.joins(:place)
        .where('places.name = ?', @place_name_filter)
    end

    if (params.has_key?(:public_entity_id))
      @incidents = @incidents.joins(:public_entity)
        .where('public_entity_id = ?', params[:public_entity_id])
    elsif (params.has_key?(:public_entity_name_appr_filter) &&
           params[:public_entity_name_appr_filter] != "" && 
           params[:public_entity_name_appr_filter] != t(:public_entity_name))
      capitalized_appr_name_filter =
        Unicode::upcase(params[:public_entity_name_appr_filter])
      @incidents = @incidents.joins(:public_entity)
        .where('public_entities.name like ?',
               "%#{capitalized_appr_name_filter}%")
    elsif (params.has_key?(:public_entity_name_filter) &&
        params[:public_entity_name_filter] != "" && 
        params[:public_entity_name_filter] != t(:public_entity_name))
      @incidents = @incidents.joins(:public_entity)
        .where('public_entities.name = ?',
               "#{params[:public_entity_name_filter]}")
    end

    @pageno = params[:pageno].to_i
    @pagesize = params[:pagesize] || PAGE_SIZE
    if (@pageno > 0)
      @incidents = @incidents.limit(@pagesize)
        .offset((@pageno - 1) * @pagesize)
    end
            
    respond_to do |format|
      format.html { render action: "index" }
      format.json { render :json => @incidents, 
        :include => INCLUDE_INCIDENT_JSON_DESC[:include] }
    end
  end
  
  # GET /incidents/1
  # GET /incidents/1.json
  def show
    @incident = Incident.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @incident,
        :include => INCLUDE_INCIDENT_JSON_DESC[:include] }
    end
  end

  # GET /incidents/new
  # GET /incidents/new.json
  def new
    @incident = Incident.new

    if params[:praise]
      @incident.praise = params[:praise]
    end

    respond_to do |format|
      format.html # new.html.erb
      format.js
      format.json { render json: @incident }
    end
  end

  # GET /incidents/1/edit
  def edit
    @incident = Incident.find(params[:id])
    @praise = @incident.praise.to_s
  end

  # POST /incidents
  # POST /incidents.json
  def create
    @incident = Incident.new(params[:incident])

    captcha_ok = verify_recaptcha(:model => @incident)
    
    could_not_save_place = false
    
    if captcha_ok
      if params.has_key?(:public_entity_name)
        public_entity_name = params[:public_entity_name]
        public_entity_query = PublicEntity.where(:name => public_entity_name)
        if public_entity_query.any?
          @incident.public_entity_id = public_entity_query.first.id
        end
      end
      if params.has_key?(:place)
        place_query = Place.where(:name => params[:place][:name])
        if place_query.any?
          @incident.place_id = place_query.first.id
        else
          @place = Place.new()
          @place.name = params[:place][:name]
          @place.longitude = params[:place][:longitude]
          @place.latitude = params[:place][:latitude]
          @place.address = params[:place][:address]
          if @place.save()
            @incident.place_id = @place.id
          else
            could_not_save_place = true
          end
        end
      end
    end

    respond_to do |format|
      if captcha_ok && !could_not_save_place && @incident.save
        if session[:used_id]
          format.html { redirect_to @incident,
            notice: 'Incident was successfully created.' }
        else
          format.html { redirect_to thank_you_incident_path(@incident) }
        end
        format.json { render json: @incident, status: :created,
          location: @incident }
      else
        format.html { render action: "new" }
        format.json { render json: @incident.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /incidents/1
  # PUT /incidents/1.json
  def update
    @incident = Incident.find(params[:id])

    respond_to do |format|
      if @incident.update_attributes(params[:incident])
        format.html { redirect_to @incident, notice: 'Incident was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @incident.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /incidents/1
  # DELETE /incidents/1.json
  def destroy
    @incident = Incident.find(params[:id])
    @incident.destroy

    respond_to do |format|
      format.html { redirect_to incidents_url }
      format.json { head :no_content }
    end
  end

  # GET /incidents/total_given
  def total_given
    sum = Incident.where(:approval_status => Incident::APPROVED_STATUS)
      .sum("money_given")
        
    respond_to do |format|     
      format.json { render json: sum}
    end
  end

  def thank_you
    respond_to do |format|
      format.html # thank_you.html.erb
    end
  end
  
end
