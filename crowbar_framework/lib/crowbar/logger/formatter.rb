#
# Copyright 2014, SUSE LINUX Products GmbH
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

module Crowbar
  module Logger
    class Formatter < ::Logger::Formatter
      include ActiveSupport::TaggedLogging::Formatter
      FORMAT = "%s, [%s#%d] %5s -- %s\n"
      THREAD_FORMAT = "%s, [%s#%d:%s] %5s -- %s\n"

      def call(severity, time, progname, msg)
        threads = ENV["CROWBAR_THREADS"]
        # if env var is not set, default is multi-threaded
        if threads.to_s.empty? || threads.to_i > 1
          # there's no API to get an id from a thread object, so let's cheat
          thread_id = Thread.current.inspect.gsub(/^#<Thread:([^ ]*) .*/, "\\1")
          format(
            THREAD_FORMAT,
            severity[0..0],
            format_datetime(time),
            $$,
            thread_id,
            severity,
            msg2str(msg)
          )
        else
          format(
            FORMAT,
            severity[0..0],
            format_datetime(time),
            $$,
            severity,
            msg2str(msg)
          )
        end
      end

      private

      # Comes from ruby/logger.rb
      def format_datetime(time)
        if @datetime_format.nil?
          time.strftime("%Y-%m-%dT%H:%M:%S.#{format("%06d ", time.usec)}")
        else
          time.strftime(@datetime_format)
        end
      end

      def msg2str(msg)
        case msg
        when ::String
          msg
        when ::Exception
          "#{msg.message} (#{msg.class})\n" <<
            (msg.backtrace || []).join("\n")
        else
          msg.inspect
        end
      end
    end
  end
end
