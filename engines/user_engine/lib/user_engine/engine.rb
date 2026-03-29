module UserEngine
  class Engine < ::Rails::Engine
    isolate_namespace UserEngine

    # Tell Rails to autoload engine's graphql + events directories
    config.autoload_paths += %W[
      #{root}/app/graphql
      #{root}/app/events
    ]
  end
end
