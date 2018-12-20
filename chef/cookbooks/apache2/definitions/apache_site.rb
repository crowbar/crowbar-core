#
# Cookbook Name:: apache2
# Definition:: apache_site
#
# Copyright 2008-2009, Opscode, Inc.
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

define :apache_site, enable: true do
  include_recipe "apache2"
  if node[:platform_family] == "suse"
    if not params[:enable]
      ruby_block "disabling vhost #{params[:name]}" do
        block do
          filename = "#{node[:apache][:dir]}/vhosts.d/#{params[:name]}"
          Chef::Log.debug("Renaming #{filename} to #{filename}.disabled")
          ::File.rename(filename, "#{filename}.disabled")
        end
        only_if do
          ::File.exist?("#{node[:apache][:dir]}/vhosts.d/#{params[:name]}")
        end
        notifies :reload, "service[apache2]", :immediately
      end
    else
      ruby_block "enabling vhost #{params[:name]}" do
        block do
          filename = "#{node[:apache][:dir]}/vhosts.d/#{params[:name]}"
          if File.exist?("#{filename}.disabled")
            Chef::Log.debug("Renaming #{filename}.disabled to #{filename}")
            File.rename("#{filename}.disabled", filename)
          end
        end
        not_if do
          File.exist?(filename)
        end
        notifies :reload, "service[apache2]", :immediately
      end
    end
  else
    if params[:enable]
      execute "a2ensite #{params[:name]}" do
        command "/usr/sbin/a2ensite #{params[:name]}"
        notifies :reload, "service[apache2]", :immediately
        not_if do
          ::File.symlink?("#{node[:apache][:dir]}/sites-enabled/#{params[:name]}") or
            ::File.symlink?("#{node[:apache][:dir]}/sites-enabled/000-#{params[:name]}")
        end
        only_if do ::File.exists?("#{node[:apache][:dir]}/sites-available/#{params[:name]}") end
      end
    else
      execute "a2dissite #{params[:name]}" do
        command "/usr/sbin/a2dissite #{params[:name]}"
        notifies :reload, "service[apache2]", :immediately
        only_if do ::File.symlink?("#{node[:apache][:dir]}/sites-enabled/#{params[:name]}") end
      end
    end
  end
end
