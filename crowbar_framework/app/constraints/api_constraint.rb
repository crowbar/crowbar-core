#
# Copyright 2016, SUSE Linux GmbH
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

class ApiConstraint
  attr_reader :versions

  def initialize(*versions)
    @versions = versions.map { |v| v.to_s.split(".").map(&:to_i) }
  end

  def matches?(request)
    versions.any? do |major, minor|
      version_mime = %r(^application/vnd\.crowbar\.v(?<major>\d+).(?<minor>\d+)\+json$)

      versions_requested = version_mime.match(request.accept)
      !versions_requested.nil? &&
        versions_requested[:major].to_i == major &&
        versions_requested[:minor].to_i <= minor
    end
  end
end
