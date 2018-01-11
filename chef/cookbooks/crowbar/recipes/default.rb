#
# Cookbook Name:: crowbar
# Recipe:: default
#
# Copyright 2011, Opscode, Inc. and Dell, Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

unless node[:platform_family] == "suse"
  include_recipe "bluepill"
end

pkglist = ()
logdir = "/var/log/crowbar"
crowbar_home = "/var/lib/crowbar"

case node[:platform_family]
when "debian"
  pkglist = %w(
    curl
    sudo
    postgresql-9.4
    postgresql-server-dev-9.4
    libshadow-ruby1.8
    markdown
  )
  unless search(:node, "platform_family:windows").empty?
    pkglist.push "smbclient"
  end
when "rhel"
  pkglist = %w(
    curl
    sudo
    postgresql94-server
    postgresql-libs
    python-markdown
  )
  unless search(:node, "platform_family:windows").empty?
    pkglist.push "samba-client"
  end
when "suse"
  pkglist = %w(
    curl
    sudo
    postgresql94-server

    ruby2.1-rubygem-activerecord-session_store
    ruby2.1-rubygem-activeresource
    ruby2.1-rubygem-active_model_serializers
    ruby2.1-rubygem-chef
    ruby2.1-rubygem-uglifier
    ruby2.1-rubygem-dotenv
    ruby2.1-rubygem-haml-rails
    ruby2.1-rubygem-hashie
    ruby2.1-rubygem-js-routes
    ruby2.1-rubygem-kwalify
    ruby2.1-rubygem-mime-types
    ruby2.1-rubygem-mixlib-shellout
    ruby2.1-rubygem-ohai-6
    ruby2.1-rubygem-rails-4_2
    ruby2.1-rubygem-puma
    ruby2.1-rubygem-ruby-shadow
    ruby2.1-rubygem-sass-rails
    ruby2.1-rubygem-simple-navigation
    ruby2.1-rubygem-simple_navigation_renderers
    ruby2.1-rubygem-pg
    ruby2.1-rubygem-syslogger
    ruby2.1-rubygem-yaml_db
  )
  unless search(:node, "platform_family:windows").empty?
    pkglist.push "samba-client"
  end
end

pkglist.each do |p|
  package p do
    action :install
  end
end

unless node[:platform_family] == "suse"
  gemlist = %w(
    activerecord-session_store
    activeresource
    chef
    uglifier
    dotenv
    dotenv-deployment
    haml-rails
    hashie
    js-routes
    kwalify
    mime-types
    mixlib-shellout
    ohai
    rails
    sass-rails
    simple-navigation
    simple_navigation_renderers
    pg
    syslogger
    puma
  )

  gemlist.each do |g|
    gem_package g do
      action :install
    end
  end
end

group "crowbar"

user "crowbar" do
  comment "Crowbar User"
  gid "crowbar"
  home crowbar_home
  password "$6$afAL.34B$T2WR6zycEe2q3DktVtbH2orOroblhR6uCdo5n3jxLsm47PBm9lwygTbv3AjcmGDnvlh0y83u2yprET8g9/mve."
  shell "/bin/bash"
  supports manage_home: true
  not_if "egrep -qi '^crowbar:' /etc/passwd"
end

directory "/root/.chef" do
  owner "root"
  group "root"
  mode "0700"
  action :create
end

cookbook_file "/etc/profile.d/crowbar.sh" do
  owner "root"
  group "root"
  mode "0755"
  action :create
  source "crowbar.sh"
end

directory "/etc/sudoers.d" do
  owner "root"
  group "root"
  mode "0750"
  action :create
end

ruby_block "Ensure /etc/sudoers.d is included in sudoers" do
  block do
    f = Chef::Util::FileEdit.new("/etc/sudoers")
    f.insert_line_if_no_match(/^#includedir \/etc\/sudoers.d\/?$/,
                              "#includedir /etc/sudoers.d")
    f.write_file
  end
  only_if { File.exists?("/etc/sudoers") }
end

cookbook_file "/etc/sudoers.d/crowbar" do
  owner "root"
  group "root"
  mode "0440"
  action :create
  source "sudoers.crowbar"
end

cookbook_file "/root/.chef/knife.rb" do
  owner "root"
  group "root"
  mode "0600"
  action :create
  source "knife.rb"
end

bash "Add crowbar chef client" do
  environment({"EDITOR" => "/bin/true", "HOME" => "/root"})
  code "knife client create crowbar -a --file /opt/dell/crowbar_framework/config/client.pem -u chef-webui -k /etc/chef/webui.pem "
  not_if "export HOME=/root;knife client list -u crowbar -k /opt/dell/crowbar_framework/config/client.pem"
end

file "/opt/dell/crowbar_framework/tmp/queue.lock" do
  owner "crowbar"
  group "crowbar"
  mode "0644"
  action :create
end
file "/opt/dell/crowbar_framework/tmp/ip.lock" do
  owner "crowbar"
  group "crowbar"
  mode "0644"
  action :create
end

unless node[:platform_family] == "suse"
  file "/var/run/crowbar-webserver.pid" do
    owner "crowbar"
    group "crowbar"
    mode "0644"
    action :create
  end
end

directory "/var/run/crowbar" do
  owner "crowbar"
  group "crowbar"
  mode "0700"
  action :create
end

# mode 0755 so subdirs can be nfs mounted to admin-exported shares
directory logdir do
  owner "crowbar"
  group "crowbar"
  mode "0755"
  action :create
end

directory "#{logdir}/chef-client" do
  owner "crowbar"
  group "crowbar"
  mode "0750"
  action :create
end

unless node["crowbar"].nil? or node["crowbar"]["users"].nil? or node["crowbar"]["realm"].nil?
  web_port = node["crowbar"]["web_port"] || 3000
  realm = node["crowbar"]["realm"]
  workers = node["crowbar"]["workers"] || 2
  threads = node["crowbar"]["threads"] || 16
  chef_solr_heap = node["crowbar"]["chef"]["solr_heap"] || 256
  chef_solr_data = if node["crowbar"]["chef"]["solr_tmpfs"]
    "/dev/shm/solr_data"
  else
    "/var/cache/chef/solr/data"
  end

  users = {}
  node["crowbar"]["users"].each do |k,h|
    next if h["disabled"]
    # Fix passwords into digests.
    h["digest"] = Digest::MD5.hexdigest("#{k}:#{realm}:#{h["password"]}") if h["digest"].nil?
    users[k] = h
  end

  template "/opt/dell/crowbar_framework/htdigest" do
    source "htdigest.erb"
    variables(users: users, realm: realm)
    owner "root"
    group node[:apache][:group]
    mode "0640"
  end
else
  web_port = 3000
  realm = nil
  workers = 2
  threads = 16
  chef_solr_heap = 256
  chef_solr_data = "/var/cache/chef/solr/data"
end

# Remove rainbows configuration, dating from before the switch to puma
file "/opt/dell/crowbar_framework/rainbows.cfg" do
  action :delete
end

template "/etc/sysconfig/crowbar" do
  source "sysconfig.crowbar.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    web_host: "127.0.0.1",
    web_port: web_port,
    workers: workers,
    threads: threads
  )
end

service "chef-solr" do
  supports status: true, restart: true
  action :nothing
end

template "/etc/chef/solr.rb" do
  source "chef-solr.rb.erb"
  owner "root"
  group "chef"
  mode "0640"
  variables(
    chef_solr_heap: chef_solr_heap,
    chef_solr_data: chef_solr_data
  )
  notifies :restart, "service[chef-solr]", :delayed
end

# Make systemd restart chef services (and their deps) on failure
utils_systemd_service_restart "rabbitmq-server"
utils_systemd_service_restart "couchdb"
utils_systemd_service_restart "chef-solr"
utils_systemd_service_restart "chef-expander"
utils_systemd_service_restart "chef-server"

if node[:platform_family] == "suse"
  # With new erlang packages, we move to a system-wide epmd service, with a
  # epmd.socket unit. This is enabled by default but only listens on 127.0.0.1,
  # while we need it to listen on the admin network too.

  # on initial setup, we have no info about addresses, so we won't get the
  # admin address
  admin_network = BarclampLibrary::Barclamp::Inventory.get_network_by_type(node, "admin")
  admin_address = admin_network.nil? ? nil : admin_network.address

  directory "/etc/systemd/system/epmd.socket.d" do
    owner "root"
    group "root"
    mode 0o755
    action :create
    not_if { admin_address.nil? }
    only_if "grep -q Requires=epmd.service /usr/lib/systemd/system/rabbitmq-server.service"
  end

  template "/etc/systemd/system/epmd.socket.d/port.conf" do
    source "epmd.socket-port.conf.erb"
    owner "root"
    group "root"
    mode 0o644
    variables(
      listen_address: admin_address
    )
    not_if { admin_address.nil? }
    only_if "grep -q Requires=epmd.service /usr/lib/systemd/system/rabbitmq-server.service"
  end

  bash "reload systemd for epmd.socket extension" do
    code "systemctl daemon-reload"
    action :nothing
    subscribes :run, "template[/etc/systemd/system/epmd.socket.d/port.conf]", :immediate
  end

  # Now do the config for the crowbar service

  cookbook_file "/etc/tmpfiles.d/crowbar.conf" do
    owner "root"
    group "root"
    mode "0644"
    action :create
    source "crowbar.tmpfiles"
  end

  bash "create tmpfiles.d files for crowbar" do
    code "systemd-tmpfiles --create /etc/tmpfiles.d/crowbar.conf"
    action :nothing
    subscribes :run, resources("cookbook_file[/etc/tmpfiles.d/crowbar.conf]"), :immediately
  end

  service "crowbar" do
    action :enable
  end
  # No need for utils_systemd_service_restart: Restart= is already in the .service file
else
  %w(chef-server-api chef-server-webui chef-solr rabbitmq-server).each do |f|
    file "/etc/logrotate.d/#{f}" do
      action :delete
    end
  end

  cookbook_file "/etc/logrotate.d/chef-server"

  template "/etc/bluepill/crowbar-webserver.pill" do
    source "crowbar-webserver.pill.erb"
    variables(logdir: logdir, crowbar_home: crowbar_home)
  end

  bluepill_service "crowbar-webserver" do
    action [:load, :start]
  end

  cookbook_file "/etc/init.d/crowbar" do
    owner "root"
    group "root"
    mode "0755"
    action :create
    source "crowbar"
  end

  ["3", "5", "2"].each do |i|
    link "/etc/rc#{i}.d/S99xcrowbar" do
      action :create
      to "/etc/init.d/crowbar"
      not_if "test -L /etc/rc#{i}.d/S99xcrowbar"
    end
  end
end

include_recipe "apache2"
include_recipe "apache2::mod_proxy"
include_recipe "apache2::mod_proxy_balancer"
include_recipe "apache2::mod_proxy_http"
include_recipe "apache2::mod_rewrite"
include_recipe "apache2::mod_slotmem_shm"
include_recipe "apache2::mod_socache_shmcb"
include_recipe "apache2::mod_auth_digest"
include_recipe "apache2::mod_ssl"
include_recipe "apache2::mod_headers"

if node[:crowbar][:apache][:ssl]
  if !node[:crowbar][:apache][:generate_certs]
    if ::File.size? node[:crowbar][:apache][:ssl_crt_file]
      Chef::Log.info("SSL certificates for Crowbar HTTPS exist.")
    else
      message = "The file \"#{node[:crowbar][:apache][:ssl_crt_file]}\" does not exist or is empty."
      Chef::Log.fatal(message)
      raise message
    end
  else
    package "apache2-utils"

    Chef::Log.info("Generating SSL certificates for Crowbar.")
    bash "generate apache certificate" do
      code <<-GENSSLCERT
        (umask 377 ; /usr/bin/gensslcert -C crowbar )
      GENSSLCERT
      not_if { ::File.size?(node[:crowbar][:apache][:ssl_crt_file]) }
    end
  end
end

template "#{node[:apache][:dir]}/vhosts.d/crowbar.conf" do
  source "apache.conf.erb"
  mode 0644

  variables(
    realm: realm,
    use_ssl: node[:crowbar][:apache][:ssl],
    ssl_crt_file: node[:crowbar][:apache][:ssl_crt_file],
    ssl_key_file: node[:crowbar][:apache][:ssl_key_file],
    ssl_crt_chain_file: node[:crowbar][:apache][:ssl_crt_chain_file]
  )

  notifies :reload, resources(service: "apache2")
end

template "#{node[:apache][:dir]}/conf.d/crowbar-rails.conf.partial" do
  source "crowbar-rails.conf.partial.erb"
  mode 0644

  variables(
    port: web_port
  )

  notifies :reload, resources(service: "apache2")
end

cookbook_file "/etc/cron.hourly/crowbar-sessions-sweep" do
  source "crowbar-sessions-sweep.cron"
  mode 0755
end

# The below code swiped from:
# https://github.com/opscode-cookbooks/chef-server/blob/chef10/recipes/default.rb
# It will automaticaly compact the couchdb database when it gets too large.
require "open-uri"

http_request "compact chef couchDB" do
  action :post
  url "#{Chef::Config[:couchdb_url]}/chef/_compact"
  only_if do
    begin
      open("#{Chef::Config[:couchdb_url]}/chef")
      JSON::parse(open("#{Chef::Config[:couchdb_url]}/chef").read)["disk_size"] > 100_000_000
    rescue OpenURI::HTTPError
      nil
    end
  end
end

%w(nodes roles registrations clients data_bags data_bag_items users checksums cookbooks sandboxes environments id_map).each do |view|
  http_request "compact chef couchDB view #{view}" do
    action :post
    url "#{Chef::Config[:couchdb_url]}/chef/_compact/#{view}"
    only_if do
      begin
        open("#{Chef::Config[:couchdb_url]}/chef/_design/#{view}/_info")
        JSON::parse(open("#{Chef::Config[:couchdb_url]}/chef/_design/#{view}/_info").read)["view_index"]["disk_size"] > 100_000_000
      rescue OpenURI::HTTPError
        nil
      end
    end
  end
end
