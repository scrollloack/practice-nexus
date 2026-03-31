# frozen_string_literal: true

module AuditEngine
  class Engine < ::Rails::Engine
    isolate_namespace AuditEngine

    config.autoload_paths += %W[
      #{root}/app/consumers
      #{root}/app/models
    ]
  end
end
