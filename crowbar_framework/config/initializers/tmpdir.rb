#
# Copyright 2011-2013, Dell
# Copyright 2013-2015, SUSE Linux GmbH
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

class Dir
  class << self
    def mktmpdir_with_rails_context(prefix_suffix = nil, tmp_dir = nil, *rest)
      # set tmp dir to application tmp dir
      tmp_dir = tmpdir_with_rails_context if tmp_dir.nil?
      # determine the caller
      call = caller_locations(1, 1).first.label
      # set caller prefix to the directory name
      # this makes debugging easier in case a tmp dir is not correctly removed
      prefix_suffix = "#{call}-" if prefix_suffix.nil? && call

      # call the old tmpdir with the new parameters
      mktmpdir_without_rails_context(prefix_suffix, tmp_dir, *rest)
    end

    alias_method_chain :mktmpdir, :rails_context

    def tmpdir_with_rails_context(systemdir = false)
      if systemdir
        tmpdir_without_rails_context
      else
        Rails.root.join("tmp").to_s
      end
    end

    alias_method_chain :tmpdir, :rails_context
  end
end
