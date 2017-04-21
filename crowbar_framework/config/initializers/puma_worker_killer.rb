PumaWorkerKiller.config do |config|
  ram = File.foreach("/proc/meminfo").grep(/MemTotal/)[0].split[1].to_i
  config.ram           = ram / 1000 # total RAM in MB
  config.frequency     = 60 # checking frequency in seconds
  config.percent_usage = 0.98 # RAM utilization
  config.rolling_restart_frequency = 60 * 60 * 12 # 12 hours in seconds
  config.reaper_status_logs = false # setting this to false will not log lines like:
  # PumaWorkerKiller: Consuming 100 mb with master and 2 workers.
end
