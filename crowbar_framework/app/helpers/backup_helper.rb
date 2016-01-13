#
# Copyright 2015, SUSE LINUX GmbH
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

module BackupHelper
  def download_backup_button(backup)
    button_to(
      t("download"),
      backup_download_path(
        backup.name,
        backup.created_at
      ),
      method: :get,
      class: "btn btn-default"
    )
  end

  def delete_backup_button(backup)
    link_to(
      t("delete"),
      backup_delete_path(
        name: backup.name,
        created_at: backup.created_at
      ),
      method: :delete,
      class: "btn btn-danger",
      data: { confirm: t("are_you_sure") }
    )
  end

  def restore_backup_button(backup)
    button_to(
      t(".restore"),
      restore_path(
        name: backup.name,
        created_at: backup.created_at
      ),
      method: :post,
      class: "btn btn-success",
      data: { confirm: t(".restore_warning") }
    )
  end
end
