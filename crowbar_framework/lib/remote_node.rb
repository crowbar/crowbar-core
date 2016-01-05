#
# Copyright 2011-2013, Dell
# Copyright 2013-2014, SUSE LINUX Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "socket"

module RemoteNode
  extend self

  # Wait for the host to come up and reach a certain runlevel
  # so we can send ssh commands to it
  # @param host [string] hostname or IP
  # @param timeout [integer] timeout in seconds

  def ready?(host, timeout = 60, sleep_time = 10, options = {})
    timeout_at = Time.now + timeout
    ip = resolve_host(host)
    msg = "Waiting for host #{host} (#{ip}); next attempt in #{sleep_time} seconds until #{timeout_at}"

    nobj = NodeObject.find_node_by_name(host)
    reboot_requesttime = nobj[:crowbar_wall][:wait_for_reboot_requesttime] || 0

    wait_until(msg, timeout_at.to_i, sleep_time, options) do
      port_open?(ip, 22) && reboot_done?(ip, reboot_requesttime, options) && ssh_cmd(ip, runlevel_check_cmd(host))
    end
  end

  # wait until no other chef-clients are currently running on the host
  def chef_ready?(host, timeout = 60, sleep_time = 10, options = {})
    timeout_at = Time.now + timeout
    ip = resolve_host(host)
    msg = "Waiting for already running chef-client on #{host} (#{ip}); next attempt in #{sleep_time} seconds until #{timeout_at}"
    wait_until(msg, timeout_at.to_i, sleep_time, options) do
      port_open?(ip, 22) && !chef_clients_running?(ip)
    end
  end

  def reboot_done?(host_or_ip, reboot_requesttime, options = {})
    # if reboot_requesttime is zero, we don't know when the reboot was requested.
    # in this case return true so the process can continue
    if reboot_requesttime > 0
      boottime = ssh_cmd_get_boottime(host_or_ip, options)
      if boottime > 0 && boottime <= reboot_requesttime
        false
      else
        true
      end
    else
      true
    end
  end

  # get boot time of the given host or 0 if command can not be executed
  def ssh_cmd_get_boottime(host_or_ip, options = {})
    logger = options.fetch(:logger, nil)

    ssh_cmd = ssh_cmd_base(host_or_ip)
    ssh_cmd << "'echo $(($(date +%s) - $(cat /proc/uptime|cut -d \" \" -f 1|cut -d \".\" -f 1)))'"
    ssh_cmd = ssh_cmd.map(&:chomp).join(" ")
    retval = `#{ssh_cmd}`.split(" ")[0].to_i
    if $?.exitstatus != 0
      msg = "ssh-cmd '#{ssh_cmd}' to get datetime not successful"
      logger ? logger.info(msg) : puts(msg)
      retval = 0
    end
    retval
  end

  def ssh_cmd(host_or_ip, cmd)
    ssh = ssh_cmd_base(host_or_ip)
    ssh << cmd
    system(*ssh)
  end

  def pipe_ssh_cmd(host_or_ip, cmd, stdin)
    ssh = ssh_cmd_base(host_or_ip)
    ssh << cmd
    Open3.capture3(*ssh, stdin_data: stdin)
  end

  private

  # are there some chef-clients running on the host?
  # chef-client daemon started by pid 1 is not counted
  def chef_clients_running?(host_or_ip)
    ssh_cmd = ssh_cmd_base(host_or_ip)
    ssh_cmd << "'if test -f /var/chef/cache/chef-client-running.pid; then flock -n /var/chef/cache/chef-client-running.pid true; elif test -f /var/cache/chef/chef-client-running.pid; then flock -n /var/cache/chef/chef-client-running.pid true; fi'"
    ssh_cmd = ssh_cmd.map(&:chomp).join(" ")
    res = `#{ssh_cmd}`
    case $?.exitstatus
    when 0
      return false
    else
      return true
    end
  end

  # Workaround for similar issue
  # http://projects.puppetlabs.com/issues/2776
  def resolve_host(host)
    `dig +short #{host} | head -n1`.rstrip
  end

  def runlevel_check_cmd(host)
    if node_redhat?(host)
      'runlevel | grep "N 3"'
    else
      "last | head -n1 | grep -vq down"
    end
  end

  def node_redhat?(host)
    nobj = NodeObject.find_node_by_name(host)
    nobj && nobj[:platform_family] == "rhel"
  end

  # Polls until yielded block returns true or a timeout is reached
  def wait_until(msg, timeout_at, sleep_time = 10, options = {})
    logger = options.fetch(:logger, nil)

    done = block_given? ? yield : false

    while Time.now.to_i < timeout_at && !done do
      done = block_given? ? yield : false

      unless done
        logger ? logger.info(msg) : puts(msg)
        sleep(sleep_time)
      end
    end

    done
  end

  # Basic ssh parameters used for different commands on the remote host
  def ssh_cmd_base(host_or_ip)
    return ["sudo", "-i", "-u", "root", "--", "ssh", "-o", "TCPKeepAlive=no", "-o", "ServerAliveInterval=15", "root@#{host_or_ip}"]
  end

  def port_open?(ip, port)
    sock = nil
    begin
      sock = TCPSocket.new(ip, port)
    rescue => e
      false
    else
      sock.close
      true
    end
  end
end
