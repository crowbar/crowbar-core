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

# FIXME: WORKAROUND
# In case the database connection gets cut, ActiveRecord will not recognize that the connection is
# broken until the next access attempt. In this case it will raise the StatementInvalid error.
# In our case this happens when we apply a proposal e.g. provisioner on the admin node.
module ActiveRecord
  class Base
    def save(*args)
      super
    rescue ActiveRecord::StatementInvalid => e
      raise e unless e.original_exception.class == PG::ConnectionBad

      Rails.logger.warn("Database connection broken, force ActiveRecord database reconnect...")
      ActiveRecord::Base.connection.reconnect!
      super
    end
  end
end
