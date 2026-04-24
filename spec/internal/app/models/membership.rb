# frozen_string_literal: true

# Join model linking users to groups
class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :group
end
