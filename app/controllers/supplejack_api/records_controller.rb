# The majority of the Supplejack API code is Crown copyright (C) 2014, New Zealand Government, 
# and is licensed under the GNU General Public License, version 3.
# One component is a third party component. See https://github.com/DigitalNZ/supplejack_api for details. 
# 
# Supplejack was created by DigitalNZ at the National Library of NZ and 
# the Department of Internal Affairs. http://digitalnz.org/supplejack

module SupplejackApi
  class RecordsController < ApplicationController
    
    skip_before_filter :authenticate_user!, :only => [:source, :status]
    skip_before_filter :verify_limits!,     :only => [:source, :status]

  	respond_to :json, :xml, :rss

    def index
      @search = Search.new(params)
      @search.request_url = request.original_url
      @search.scope = current_user
      
      begin
        if @search.valid?
          respond_with @search, serializer: SearchSerializer
        else
          render request.format.to_sym => {errors: @search.errors}, status: :bad_request
        end
      rescue RSolr::Error::Http => e
        render request.format.to_sym => {:errors => solr_error_message(e) }, :status => :bad_request 
      rescue Sunspot::UnrecognizedFieldError => e
        render request.format.to_sym => {:errors => e.to_s }, :status => :bad_request 
      end
    end

    def show
      begin
        @record = Record.custom_find(params[:id], current_user, params[:search])

        respond_with @record, serializer: RecordSerializer
      rescue Mongoid::Errors::DocumentNotFound
        render request.format.to_sym => {:errors => "Record with ID #{params[:id]} was not found"}, :status => :not_found 
      end
    end

    def status
	  	render nothing: true
	  end

    # This options are merged with the serializer options. Which will allow the serializer
    # to know which fields to render for a specific request
    #
    def default_serializer_options
      default_options = {}
      @search ||= Search.new(params)
      default_options.merge!({:fields => @search.field_list}) if @search.field_list.present?
      default_options.merge!({:groups => @search.group_list}) if @search.group_list.present?
      default_options
    end
  end
end
