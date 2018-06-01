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

before_fork do
  PumaWorkerKiller.start
end

on_worker_boot do
  ::ActiveSupport.on_load(:active_record) do
    config = Rails.application.config.database_configuration[Rails.env]
    config["pool"] = ENV["CROWBAR_THREADS"] || 16

    ::ActiveRecord::Base.establish_connection(config)
  end
end

[
  "tmp/sessions",
  "tmp/sockets",
  "tmp/cache"
].each do |name|
  FileUtils.mkdir_p File.join(ROOT, name)
end

# When starting the process during the upgrade (after reboot),
# mark the end of "admin server upgrade" step.
if File.exist?("/var/lib/crowbar/upgrade/7-to-8-upgrade-running") &&
    !File.exist?("/var/run/crowbar/admin-server-upgrading")
  CROWBAR_LIB_DIR = "/opt/dell/crowbar_framework/lib".freeze
  $LOAD_PATH.push CROWBAR_LIB_DIR if Dir.exist?(CROWBAR_LIB_DIR)

  require "logger"
  require "crowbar/upgrade_status"
  upgrade_status = ::Crowbar::UpgradeStatus.new(Logger.new(Logger::STDOUT))
  upgrade_status.end_step if upgrade_status.current_step == :admin
end

stdout_redirect(
  "/var/log/crowbar/production.log",
  "/var/log/crowbar/production.log",
  true
)
