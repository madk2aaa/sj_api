# The majority of the Supplejack API code is Crown copyright (C) 2014, New Zealand Government, 
# and is licensed under the GNU General Public License, version 3.
# One component is a third party component. See https://github.com/DigitalNZ/supplejack_api for details. 
# 
# Supplejack was created by DigitalNZ at the National Library of NZ and 
# the Department of Internal Affairs. http://digitalnz.org/supplejack

module SupplejackApi
  class ConceptSearchSerializer < ActiveModel::Serializer
    
    ConceptSchema.groups.keys.each do |group|
      define_method("#{group}?") do
        return false unless options[:groups].try(:any?)
        self.options[:groups].include?(group)  
      end
    end

    def serializable_hash    
      hash = {}
      hash[:result_count] = object.total
      hash[:results] = records_serialized_array
      hash[:per_page] = object.per_page
      hash[:page] = object.page
      hash[:request_url] = object.request_url
      hash[:solr_request_params] = object.solr_request_params if object.solr_request_params
      hash[:warnings] = object.warnings if object.warnings.present?
      hash[:suggestion] = object.collation if object.options[:suggest]
      hash
    end
    
    def json_facets
      facets = {}

      object.facets.map do |facet|
        rows = {}
        facet.rows.each do |row|
          rows[row.value] = row.count
        end

        facets.merge!({facet.name => rows})
      end
      facets
    end
    
    def to_json(options={})
      rendered_json = as_json(options).to_json
      rendered_json = "#{object.jsonp}(#{rendered_json})" if object.jsonp
      rendered_json
    end
    
    def as_json(options={})
      hash = { search: serializable_hash }
      hash[:search][:facets] = json_facets
      hash
    end
    
    def records_serialized_array
      ActiveModel::ArraySerializer.new(object.results, {fields: object.field_list, groups: object.group_list, scope: object.scope})
    end

  end

end