# The majority of the Supplejack API code is Crown copyright (C) 2014, New Zealand Government, 
# and is licensed under the GNU General Public License, version 3.
# One component is a third party component. See https://github.com/DigitalNZ/supplejack_api for details. 
# 
# Supplejack was created by DigitalNZ at the National Library of NZ and 
# the Department of Internal Affairs. http://digitalnz.org/supplejack

module SupplejackApi
  class Search
    include ActiveModel::SerializerSupport
  
    INTEGER_ATTRIBUTES ||= [:page, :per_page, :facets_per_page, :facets_page, :record_type]
    
    attr_accessor :options, :request_url, :scope, :solr_request_params, :errors, :warnings, :schema_class, :model_class
  
    class_attribute :max_values
    
    self.max_values = {
      page: 100000, 
      per_page: 100, 
      facets_per_page: 150, 
      facets_page: 5000
    }
  
    def initialize(options={})
      @options = options.dup
      @options.reverse_merge!(
        facets: '', 
        and: {}, 
        or: {}, 
        without: {}, 
        page: 1, 
        per_page: 20, 
        record_type: 0, 
        facets_per_page: 10, 
        facets_page: 1, 
        sort: nil, 
        direction: 'desc', 
        fields: 'default', 
        facet_query: {}, 
        debug: nil
      )

      klass = self.class.to_s.gsub(/Search/, '')
      @schema_class = "#{klass.demodulize}Schema".constantize
      @model_class = klass.constantize
    end

    # Return an array of valid facets
    # It will remove any invalid facets in order to avoid Solr errors
    #
    def facet_list
      return @facet_list if @facet_list
  
      @facet_list = options[:facets].split(",").map {|f| f.strip.to_sym}
      @facet_list.keep_if {|f| model_class.valid_facets.include?(f) }
      @facet_list
    end

    def field_list
      return @field_list if @field_list
      valid_fields = schema_class.fields.keys.dup

      @field_list = options[:fields].split(",").map {|f| f.strip.gsub(':', '_').to_sym}
      @field_list.delete_if do |f|
        !valid_fields.include?(f)
      end
      
      @field_list
    end

    # Returns all valid groups of fields
    # The groups are extracted from the "fields" parameter
    #
    def group_list
      return @group_list if @group_list
      @group_list = options[:fields].split(',').map {|f| f.strip.to_sym}
      @group_list.keep_if {|f| model_class.valid_groups.include?(f) }
      @group_list
    end

    def query_fields
      query_field_list = nil
  
      if options[:query_fields].is_a?(String)
        query_field_list = options[:query_fields].split(',').map(&:strip).map(&:to_sym)
      elsif options[:query_fields].is_a?(Array)
        query_field_list = options[:query_fields].map(&:to_sym)
      end
  
      return nil if query_field_list.try(:empty?)
      query_field_list
    end

    def extract_range(value)
      if value.match(/^\[(\d+)\sTO\s(\d+)\]$/)
        $1.to_i..$2.to_i
      else
        value.to_i > 0 ? value.to_i : value.strip
      end
    end

    def to_proper_value(name, value)
      return false if value == 'false'
      return true if value == 'true'
      return nil if ['nil', 'null'].include?(value)
  
      value = value.strip if value.is_a?(String)
      value
    end

    # Downcase all queries before sending to SOLR, except queries
    # which have specific lucene syntax.
    #
    def text
      @text = options[:text]
      if @text.present? && !@text.match(/:\"/)
        @text.downcase!
        @text.gsub!(/ and | or | not /) {|op| op.upcase}
      end
      @text
    end

    def offset
      (page * per_page) - per_page
    end
  
    def facets_offset
      offset = (facets_page * facets_per_page) - facets_per_page
      offset < 0 ? 0 : offset
    end

    def valid?
      self.errors ||= []
      self.warnings ||= []
      self.class.max_values.each do |attribute, max_value|
        max_value = self.class.max_values[attribute]
        self.warnings << "The #{attribute} parameter can not exceed #{max_value}" if @options[attribute].to_i > max_value
      end
  
      self.solr_search_object
      self.errors.empty?
    end
  
    def records
      self.solr_search_object.results
    end
  
    def jsonp
      @options[:jsonp].present? ? @options[:jsonp] : nil
    end

    # It's currently required to make the active_model_serializers gem to work with XML
    # The XML Serialization is handled by the respective serializer
    #
    def to_xml; end

    # IMPORTANT !!!!
    #
    # Try to make this a bit prettier
    #
    INTEGER_ATTRIBUTES.each do |method|
      define_method(method) do
        value = @options[:"#{method.to_sym}"].to_i
        value = [value, self.class.max_values[method]].min if self.class.max_values[method]
        value
      end
    end

    def sort
      value = @options[:sort].to_sym
      
      begin
        field = Sunspot::Setup.for(Record).field(value)
        return value
      rescue Sunspot::UnrecognizedFieldError => e
        return 'score'
      end
    end
  
    def direction
      if ['asc', 'desc'].include?(@options[:direction])
        @options[:direction].to_sym
      else
        :desc
      end
    end

    def solr_search_object
      return @solr_search_object if @solr_search_object
      @solr_search_object = execute_solr_search
  
      if options[:debug] == 'true' && @solr_search_object.respond_to?(:query)
        self.solr_request_params = @solr_search_object.query.to_params
      end
  
      @solr_search_object
    end

    def solr_error_message(exception)
      {
        title: "#{exception.response[:status]} #{RSolr::Error::Http::STATUS_CODES[exception.response[:status].to_i]}",
        body: exception.send(:parse_solr_error_response, exception.response[:body])
      }
    end

    def method_missing(symbol, *args, &block)
      return nil unless self.solr_search_object.respond_to?(:hits)
      self.solr_search_object.send(symbol, *args)
    end

    def execute_solr_search
      search = search_builder
  
      search.build do
        keywords text, :fields => query_fields
      end
  
      execute_solr_search_and_handle_errors(search)
    end

    def execute_solr_search_and_handle_errors(search)
      begin
        self.errors ||= []
        sunspot = search.execute
      rescue RSolr::Error::Http => e
        self.errors << self.solr_error_message(e)
        Rails.logger.info e.message
        sunspot = {}
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET => e
        self.errors << 'Solr is temporarily unavailable please try again in a few seconds.'
        Rails.logger.info e.message
        sunspot = {}
      ensure
        return sunspot
      end
    end

    private
  
    # Generates the :and and :or conditions for a search object
    #
    def build_conditions
      Proc.new do
        {and: options[:and], or: options[:or]}.each do |operator, value|
          Utils.call_block(self, &recurse_conditions(operator, value))
        end
      end
    end
  
    # Detects when the key is a operator (:and, :or) and calls itself
    # recursively until it finds facets defined in Sunspot.
    #
    def recurse_conditions(key, conditions, current_operator=:and)
      Proc.new do
        case key.to_sym
        when :and
          all_of do
            conditions.each do |filter,value|
              Utils.call_block(self, &recurse_conditions(filter,value, :and))
            end
          end
        when :or
          any_of do
            conditions.each do |filter,value|
              Utils.call_block(self, &recurse_conditions(filter,value, :or))
            end
          end
        else
          Utils.call_block(self, &filter_values(key, conditions, current_operator))
        end
      end
    end
  
    # Generates a single condition. It can take a operator to
    # determine how the values within the filter are going to be
    # joined.
    #
    def filter_values(key, conditions, current_operator=:and)
      Proc.new do
        if conditions.is_a? Hash
          operator, values = conditions.first
        else
          operator = current_operator
          values = conditions
        end
  
        if values.is_a?(Array)
          case operator.to_sym
          when :or
            with(key).any_of(values)
          when :and
            with(key).all_of(values)
          else
            raise Exception.new("Expected operator (:and, :or)")
          end
        else
          if values.match(/(.+)\*$/)
            with(key).starting_with($1)
          else
            with(key, to_proper_value(key, values))
          end
        end
      end
    end
  
  end
end
