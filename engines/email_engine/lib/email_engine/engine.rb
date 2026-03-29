module EmailEngine
  class Engine < ::Rails::Engine
    isolate_namespace EmailEngine

    config.autoload_paths += %W[
      #{root}/app/consumers
      #{root}/app/mailers
    ]
  end
end
