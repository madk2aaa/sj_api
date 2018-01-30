# frozen_string_literal: true

module SupplejackApi
  # app/models/supplejack_api/record_metric.rb
  class RecordMetric
    include Mongoid::Document

    # TODO: make a flag in the supplejack initializer that this functionality can be turned on, default: false.

    field :date,                 type: Date, default: Time.zone.today
    field :record_id,            type: Integer
    field :page_views,           type: Integer, default: 0
    field :user_set_views,       type: Integer, default: 0
    field :added_to_user_sets,   type: Integer, default: 0
    field :source_clickthroughs, type: Integer, default: 0
    field :appeared_in_searches, type: Integer, default: 0

    validates :record_id, presence: true
    validates :record_id, uniqueness: { scope: :date }

    class << self
      def spawn(record_id, metric, date = Time.zone.today)
        RecordMetric.find_or_create_by(record_id: record_id, date: date).inc("#{metric}": 1)
      end
    end
  end
end
