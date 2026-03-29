module EmailEngine
  class UserMailer < ActionMailer::Base
    default from: "noreply@nexus.app"

    def welcome(user_id:, name:, email:)
      @name   = name
      @email  = email
      mail(to: email, subject: "Welcome to Nexus, #{name}!")
    end
  end
end
