#
# Copyright 2019, SUSE
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

class SES
  def self.load
    Crowbar::DataBagConfig.load("ses", "default", "ses")
  end

  def self.save(config)
    Crowbar::DataBagConfig.save("ses", "default", "ses", config)
  end

  def self.configured?
    config = self.load
    !config.nil? && !config.empty?
  end
end
