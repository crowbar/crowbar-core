#
# Copyright 2011-2013, Dell
# Copyright 2013-2016, SUSE LINUX Products GmbH
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
require "open3"

module Crowbar
  module Connection
    class SSH
      attr_reader :hostname
      attr_reader :username

      def initialize(username, hostname)
        @hostname = hostname
        @username = username
      end

      # ssh to the node and wait until the command exits (blocking)
      def exec(command)
        args = ["sudo", "-i", "-u", "root", "--",
                "timeout", "-k", "5s", "15s",
                "ssh", "-o", "ConnectTimeout=10",
                "#{username}@#{hostname}",
                %("#{command.gsub('"', '\\"')}")].join(" ")
        Open3.popen3(args) do |stdin, stdout, stderr, wait_thr|
          {
            stdout: stdout.gets(nil),
            stderr: stderr.gets(nil),
            exit_code: wait_thr.value.exitstatus
          }
        end
      end

      # Check if file exist on remote host
      def file_exist?(file_path)
        out = exec("test -e #{file_path}")
        out[:exit_code].zero?
      end

      # run command on node (nonblocking)
      def exec_in_background(command)
        # FIXME: This is horrible in terms of error handling and
        #        does not work. This will always succeed since background
        #        shell subprocesses always return 0!
        unless system("sudo", "-i", "-u", "root", "--",
            "timeout", "-k", "5s", "15s",
            "ssh", "-o", "ConnectTimeout=10", "#{username}@#{hostname}",
            "#{command} </dev/null >/dev/null 2>&1 &")
          return false
        end
        true
      end

      # execute a script in background and wait until it finishes/timouts
      # Script must generate one of the following files to indicate success
      # or failure (blocking):
      #   for SUCCESS: /varlib/crowbar/upgrade/`script_name without extension`-ok
      #   for FAILURE: /var/lib/crowbar/upgrade/`script_name without extension`-failed
      #
      # throws a RuntimeError if an error occured
      def exec_script(script_path, timeout_in_seconds)
        unless exec_in_background(script_path)
          raise "Executing of script #{script_path} has failed on #{hostname}"
        end

        base = "/var/lib/crowbar/upgrade/" + File.basename(script_path, ".sh")
        ok_file = base + "-ok"
        failed_file = base + "-failed"

        Rails.logger.debug("Waiting for #{script_path} started on #{hostname} to finish ...")

        begin
          Timeout.timeout(timeout_in_seconds) do
            loop do
              break if file_exist? ok_file

              if file_exist? failed_file
                raise "Execution of script #{script_path} on #{hostname} has failed"
              end
              sleep(5)
            end
          end
        rescue Timeout::Error
          raise "Possible error during execution of #{script_path}." \
            "Action did not finish after #{timeout_in_seconds} seconds."
        end

        # FIXME: Remove statefile after run!
      end
    end
  end
end
