# frozen_string_literal: true

class Post < ApplicationRecord
  belongs_to :user
  has_many :categorizations, dependent: :destroy
  has_many :categories, through: :categorizations

  scope :published, -> { where(published: true) }
  scope :recent, -> { order(created_at: :desc) }
end
