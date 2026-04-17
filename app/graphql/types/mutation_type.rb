# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :create_user, mutation: UserEngine::Mutations::CreateUser
    field :update_user, mutation: UserEngine::Mutations::UpdateUser
  end
end
