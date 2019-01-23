# frozen_string_literal: true

module SupplejackApi
  # app/models/supplejack_api/top_collection_metric.rb
  class TopCollectionMetric
    include Mongoid::Document

    METRICS_LOGGER = Logger.new('log/metrics.log') # run `$ touch log/metrics.log` to create metrics log file

    METRICS = %i[
      page_views
      user_set_views
      user_story_views
      added_to_user_sets
      source_clickthroughs
      appeared_in_searches
      added_to_user_stories
    ].freeze

    field :d, as: :date,               type: Date, default: Time.current.utc
    field :m, as: :metric,             type: String
    field :r, as: :results,            type: Hash
    field :c, as: :display_collection, type: String

    validates :date, presence: true
    validates :metric, presence: true
    validates :metric, uniqueness: { scope: %i[date display_collection] }

    def self.spawn
      return unless SupplejackApi.config.log_metrics == true
      enable_metrics_logger

      display_collections = find_display_collections_to_process
      dates = find_dates_to_process

      metrics = []

      dates.each do |date|
        METRICS_LOGGER.info "Current Date: #{date}"

        display_collections.each do |dc|
          METRICS_LOGGER.info "Current Display Collection: #{dc}"

          METRICS.each do |metric|
            METRICS_LOGGER.info "Current Metric: #{metric}"

            record_metrics = record_metrics_to_be_processed(date, metric, dc)

            results = calculate_results(record_metrics, metric)

            # If there are no results for a metric, date, and display collection
            # Skip to the next metric
            next if results.select { |_key, value| value.positive? }.empty?

            top_collection_metric = find_or_create_top_collection_metric(date, metric, dc)
            update_top_collection_metric(top_collection_metric, results)
            metrics.push(top_collection_metric)
          end
        end
        stamp_record_metrics(date)
      end

      disable_metrics_logger

      metrics
    end

    def self.find_dates_to_process
      METRICS_LOGGER.info 'Collecting Dates.'

      query = { :date.lt => Time.zone.now.beginning_of_day }
      SupplejackApi::RecordMetric.where(query)
                                 .map(&:date).uniq
    end

    def self.find_display_collections_to_process
      METRICS_LOGGER.info 'Collecting Collections.'

      query = { :date.lt => Time.zone.now.beginning_of_day, processed_by_top_collection_metrics: false }
      SupplejackApi::RecordMetric.where(query)
                                 .map(&:display_collection).uniq
    end

    def self.calculate_results(record_metrics, metric)
      record_metrics.each_with_object({}) do |record, hash|
        hash[record.record_id.to_s] = record.send(metric)
      end
    end

    def self.update_top_collection_metric(top_collection_metric, results)
      if top_collection_metric.results.blank?
        top_collection_metric.update(results: results)
      else
        merged_results = top_collection_metric.results.merge(results) { |_key, a, b| a + b }
        merged_results = merged_results.sort_by { |_k, v| -v }.first(200).to_h

        top_collection_metric.update(results: merged_results)
      end

      METRICS_LOGGER.info "Updated Top Collection Metric: #{top_collection_metric.inspect}"
      top_collection_metric
    end

    def self.find_or_create_top_collection_metric(date, metric, display_collection)
      top_collection_metric = find_or_create_by(
        date: date,
        metric: metric,
        display_collection: display_collection
      )

      METRICS_LOGGER.info "Top Collection Metric: #{top_collection_metric.inspect}"
      top_collection_metric
    end

    def self.record_metrics_to_be_processed(date, metric, display_collection)
      SupplejackApi::RecordMetric.where(
        date: date,
        display_collection: display_collection,
        :processed_by_top_collection_metrics.in => [nil, '', false]
      ).order_by(metric => 'desc').limit(200)
    end

    def self.stamp_record_metrics(date)
      METRICS_LOGGER.info "Stamping Record Metrics for date: #{date}"
      SupplejackApi::RecordMetric.where(date: date).update_all(processed_by_top_collection_metrics: true)
    end

    def self.enable_metrics_logger
      Mongoid.logger = METRICS_LOGGER
    end

    def self.disable_metrics_logger
      Mongoid.logger = Rails.logger
    end
  end
end
