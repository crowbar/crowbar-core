require "yaml"

module Crowbar
  class UpgradeTimeouts
    def values
      @timeouts_config = begin
        YAML.load_file("/etc/crowbar/upgrade_timeouts.yml")
      rescue
        Rails.logger.debug(
          "No user provided upgrade timeouts, proceeding with the default ones."
        )
        {}
      end

      # clean up yaml config in case of there being strings
      @timeouts_config.each do |k, v|
        next if v.is_a? Integer
        Rails.logger.error(
          "Removing user configured upgrade timeout #{k} as the value provided is not an integer."
        )
        @timeouts_config.delete(k)
      end

      {
        prepare_repositories: @timeouts_config[:prepare_repositories] || 120,
        pre_upgrade: @timeouts_config[:pre_upgrade] || 300,
        upgrade_os: @timeouts_config[:upgrade_os] || 1500,
        post_upgrade: @timeouts_config[:post_upgrade] || 600,
        shutdown_services: @timeouts_config[:shitdown_services] || 600,
        evacuate_host: @timeouts_config[:evacuate_host] || 300,
        chef_upgraded: @timeouts_config[:chef_upgraded] || 1200,
        router_migration: @timeouts_config[:router_migration] || 600,
        lbaas_evacuation: @timeouts_config[:lbaas_evacuation] || 600,
        delete_pacemaker_resources: @timeouts_config[:delete_pacemaker_resources] || 600,
        delete_cinder_services: @timeouts_config[:delete_cinder_services] || 300,
        wait_until_compute_started: @timeouts_config[:wait_until_compute_started] || 60
      }
    end
  end
end
