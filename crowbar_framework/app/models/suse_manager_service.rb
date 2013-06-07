# Copyright 2013, SUSE
# 
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License. 
# You may obtain a copy of the License at 
# 
#  http://www.apache.org/licenses/LICENSE-2.0 
# 
# Unless required by applicable law or agreed to in writing, software 
# distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License. 
# 

class SuseManagerService < ServiceObject

  def initialize(thelogger)
    @bc_name = "suse_manager"
    @logger = thelogger
  end

  def create_proposal
    @logger.debug("SUSE Manager create_proposal: entering")
    base = super
    @logger.debug("SUSE Manager create_proposal: exiting")
    base
  end

  def self.allow_multiple_proposals?
    true
  end

end

