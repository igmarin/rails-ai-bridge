# frozen_string_literal: true

# Represents a group of users through memberships
class Group < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
end
