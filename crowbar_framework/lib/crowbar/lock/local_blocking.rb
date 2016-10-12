#
# Copyright 2011-2013, Dell
# Copyright 2013-2015, SUSE LINUX GmbH
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
  class Lock::LocalBlocking < Lock
    def acquire(options = {})
      logger.debug("Acquire #{name} lock enter as uid #{Process.uid}")
      ensure_lock_file_exists
      logger.debug("Acquiring #{name} lock with #{options}")
      count = 0
      # specify different bits for shared vs. exclusive locks
      bits = File::LOCK_NB
      bits |= options[:shared] ? File::LOCK_SH : File::LOCK_EX
      loop do
        count += 1
        logger.debug("Lock #{path} attempt #{count}")
        if @file.flock(bits)
          break
        end
        sleep 1
      end
      logger.debug("Acquire #{name} lock exit: #{@file.inspect}")
      @locked = true
      self
    end

    def release
      logger.debug("Release #{name} lock enter: #{@file.inspect}")
      if @file
        @file.flock(File::LOCK_UN) if locked?
        @file.close unless @file.closed?
        @file = nil
      else
        logger.warn("release called without valid file")
      end
      logger.debug("Release #{name} lock exit")
      @locked = false
      self
    end

    private

    def ensure_lock_file_exists
      @file ||= File.new(path, File::RDWR | File::CREAT, 0o644)
    rescue
      logger.error("Couldn't open #{path} for locking: #$!")
      logger.error("cwd was #{Dir.getwd})")
      raise "Couldn't open #{path} for locking: #$!"
    end
  end
end
