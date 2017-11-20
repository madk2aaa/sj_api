module SupplejackApi
  FactoryBot.define do

    factory :fragment, class: SupplejackApi::ApiRecord::RecordFragment do
      source_id             'source_name'
      priority              0
      title                 'A record'
      creator               ['John Kennedy']
      dnz_type              'Unknown'
      primary_collection    ['TAPUHI']
      thumbnail {FactoryBot.build(:thumbnail)}
    end
  end
end
