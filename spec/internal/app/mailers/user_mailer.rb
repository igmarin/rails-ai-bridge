# frozen_string_literal: true

# Mailer for user-related emails in the test application
class UserMailer < ActionMailer::Base
  def welcome(_user_id)
    mail(to: "test@example.com", subject: "Welcome")
  end
end
