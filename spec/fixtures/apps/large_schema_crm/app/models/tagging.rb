# Joins tags to other CRM records in the large-schema fixture.
class Tagging < ApplicationRecord
  belongs_to :tag
end
