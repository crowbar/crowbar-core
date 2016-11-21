ROOT = File.expand_path("../../", __FILE__)
ENVIRONMENT = ENV["CROWBAR_ENV"] || "production"

THREADS = ENV["CROWBAR_THREADS"] || 16
WORKERS = ENV["CROWBAR_WORKERS"] || 2

LISTEN = ENV["CROWBAR_LISTEN"] || "127.0.0.1"
PORT = ENV["CROWBAR_PORT"] || 3000

require "fileutils"
require "rack/test"

directory ROOT
environment ENVIRONMENT

tag "crowbar"

quiet
preload_app!

daemonize false
prune_bundler false

threads 0, THREADS

workers WORKERS
worker_timeout 60

pidfile File.join(ROOT, "tmp", "pids", "puma.pid")
state_path File.join(ROOT, "tmp", "pids", "puma.state")

bind "tcp://#{LISTEN}:#{PORT}"

on_worker_boot do
  ::ActiveSupport.on_load(:active_record) do
    config = Rails.application.config.database_configuration[Rails.env]
    config["pool"] = ENV["CROWBAR_THREADS"] || 16

    ::ActiveRecord::Base.establish_connection(config)
  end
end

[
  "tmp/pids",
  "tmp/sessions",
  "tmp/sockets",
  "tmp/cache"
].each do |name|
  FileUtils.mkdir_p File.join(ROOT, name)
end
