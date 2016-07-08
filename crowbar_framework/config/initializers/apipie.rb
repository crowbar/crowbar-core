Apipie.configure do |config|
  config.app_name                = "Crowbar"
  config.api_base_url            = ""
  config.doc_base_url            = "/apidoc"
  config.app_info                = "An openly licensed framework to build complete, easy to use \
    operational deployments. It allows for groups of physical nodes to be transformed from \
    bare-metal into a ready state production cluster within minutes."
  config.api_controllers_matcher = "#{Rails.root}/app/controllers/**/*.rb"
  config.validate                = false
end
