#
# Copyright 2011-2013, Dell
# Copyright 2013-2016, SUSE LINUX GmbH
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
  module Lock
    class Base
      attr_accessor :logger
      attr_accessor :path
      attr_accessor :name
      attr_accessor :file

      def initialize(options = {})
        @logger = options.fetch :logger, Rails.logger
        @name = options.fetch :name, "default.lock"
        @path = options.fetch :path, Rails.root.join("tmp", @name)
        @locked = false
        @file = nil
      end

      def locked?
        @locked
      end

      def with_lock
        acquire
        yield if block_given?
      ensure
        release
      end

      class << self
        def with_lock(options = {})
          new(options).with_lock do
            yield
          end
        end
      end
    end
  end
end
