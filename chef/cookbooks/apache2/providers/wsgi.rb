# Support whyrun
def whyrun_supported?
  true
end

action :create do
  if @current_resource.exists
    Chef::Log.info "#{@new_resource} already exists"
  else
    # NOTE(aplanas) @current_resource is not accesible inside the
    # coverge_by block for some reason
    current_resource = @current_resource

    converge_by("Create #{@new_resource}") do
      template _get_vhost_name do
        source "vhost-wsgi.conf.erb"
        owner node[:apache][:user]
        group node[:apache][:group]
        mode "0644"
        cookbook "apache2"
        variables(
          bind_host: current_resource.bind_host,
          bind_port: current_resource.bind_port,
          daemon_process: current_resource.daemon_process,
          user: current_resource.user,
          group: current_resource.group,
          processes: current_resource.processes,
          threads: current_resource.threads,
          process_group: current_resource.process_group,
          script_alias: current_resource.script_alias,
          directory: current_resource.directory,
          access_log: current_resource.access_log,
          error_log: current_resource.error_log,
          apache_log_dir: node[:apache][:log_dir],
        )
        notifies :reload, resources(service: "apache2"), :immediately
      end
      Chef::Log.info "#{@new_resource} created"
    end
  end
end

action :delete do
  if @current_resource.exists
    converge_by("Delete #{@new_resource}") do
      file _get_vhost_name do
        action :delete
        only_if { File.exist?(_get_vhost_name) }
        notifies :reload, resources(service: "apache2"), :immediately
      end
      Chef::Log.info "#{@new_resource} deleted"
    end
  else
    Chef::Log.info "#{@current_resource} doesn't exist - can't delete."
  end
end

def load_current_resource
  @current_resource = Chef::Resource::Apache2Wsgi.new(@new_resource.name)

  @current_resource.bind_host(@new_resource.bind_host)
  @current_resource.bind_port(@new_resource.bind_port)
  @current_resource.daemon_process(@new_resource.daemon_process)
  @current_resource.user(@new_resource.user)
  @current_resource.group(_get_group)
  @current_resource.processes(@new_resource.processes)
  @current_resource.threads(@new_resource.threads)
  @current_resource.process_group(_get_process_group)
  @current_resource.script_alias(_get_script_alias)
  @current_resource.directory(_get_directory)
  @current_resource.access_log(_get_access_log)
  @current_resource.error_log(_get_error_log)

  if ::File.exist?(_get_vhost_name)
    @current_resource.exists = true
  end

  @current_resource
end

private

def _get_vhost_name
  apache_dir = node[:apache][:dir]
  "#{apache_dir}/vhosts.d/#{@new_resource.daemon_process}.conf"
end

def _get_group
  @new_resource.group || @new_resource.user
end

def _get_process_group
  @new_resource.process_group || @new_resource.daemon_process
end

def _get_script_alias
  default_script_alias = "/srv/www/#{@new_resource.daemon_process}/app.wsgi"
  @new_resource.script_alias || default_script_alias
end

def _get_directory
  default_directory = "/srv/www/#{@new_resource.daemon_process}"
  @new_resource.directory || default_directory
end

def _get_access_log
  default_log = "#{@new_resource.daemon_process}_access.log"
  @new_resource.access_log || default_log
end

def _get_error_log
  default_log = "#{@new_resource.daemon_process}_error.log"
  @new_resource.error_log || default_log
end
