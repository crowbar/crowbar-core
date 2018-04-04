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

require "find"

class Api::Backup < ActiveRecord::Base
  belongs_to :crowbar

  attr_accessor :file

  before_validation :save_archive, on: :create, if: :upload?
  before_save :create_archive, on: :create, unless: :upload?
  after_validation :delete_archive, unless: -> { errors.empty? }
  after_destroy :delete_archive

  validates :name,
    presence: true,
    uniqueness: true,
    format: {
      with: /\A[a-zA-Z0-9\-_]+\z/,
      message: "allows only letters and numbers"
    }

  validates :migration_level,
    presence: true

  validate :validate_chef_file_extension,
    :validate_version,
    :validate_hostname,
    :validate_upload_file_extension,
    if: :upload?

  def path
    self.class.image_dir.join(filename)
  end

  def filename
    "#{name}.tar.gz"
  end

  def extract
    backup_dir = Dir.mktmpdir
    cmd = [
      "sudo",
      "tar",
      "--same-owner",
      "--same-permissions",
      "-xzf",
      path.to_s,
      "-C",
      backup_dir
    ]
    system(*cmd)
    Pathname.new(backup_dir)
  end

  def data
    @data ||= extract
  end

  def restore(options = {})
    background = options.fetch(:background, false)
    from_upgrade = options.fetch(:from_upgrade, false)

    if Crowbar::Backup::Restore.restore_steps_path.exist?
      logger.debug "Restore process is already running"
      errors.add(:base, I18n.t("backups.index.multiple_restore"))
      return false
    elsif !from_upgrade && backup_version != system_version
      logger.debug "Restoring from different Crowbar version is not allowed"
      errors.add(:base, I18n.t("backups.index.version_conflict"))
      return false
    end

    if upgrade? && !upgrade
      return false
    end

    if background
      Crowbar::Backup::Restore.new(self).restore_background
    else
      Crowbar::Backup::Restore.new(self).restore
    end
  end

  def upgrade?
    system_version > backup_version
  end

  def upgrade
    upgrade = Crowbar::Upgrade.new(self)
    if upgrade.supported?
      upgrade.upgrade
    else
      errors.add(:base, I18n.t("backups.index.upgrade_not_supported",
                               backup_version: version,
                               system_version: ENV["CROWBAR_VERSION"]))
      return false
    end
  rescue StandardError => e
    logger.error "Upgrade failed: #{e}"
    errors.add(:base, e)
    cleanup
    return false
  end

  def cleanup
    return unless @data || @data.to_s =~ /\A#{Dir.tmpdir}/

    system(
      "sudo",
      "rm",
      "-rf",
      @data.to_s
    )
    @data = nil
  end

  class << self
    def image_dir
      if Rails.env.production?
        Pathname.new("/var/lib/crowbar/backup")
      else
        Rails.root.join("storage")
      end
    end

    def attribute_names
      super.tap do |values|
        unless values.include?("file")
          values.push("file")
        end
      end
    end
  end

  protected

  def upload?
    file.present?
  end

  def create_archive
    logger.debug "Creating backup in #{self.class.image_dir}"
    if path.exist?
      errors.add(:filename, I18n.t("backups.index.invalid_filename_exists"))
      return false
    end

    dir = Dir.mktmpdir

    Crowbar::Backup::Export.new(dir).export
    Dir.chdir(dir) do
      system(
        "sudo", "tar", "czf", path.to_s, "."
      )
    end

    @data = Pathname.new(dir)
    self.version = ENV["CROWBAR_VERSION"]
    self.size = path.size
    self.migration_level = ActiveRecord::Migrator.current_version
  rescue StandardError => e
    errors.add(:base, I18n.t("backups.index.create_backup_failed", msg: e.message))
    false
  end

  def save_archive
    if file.nil?
      errors.add_on_blank :file
      return false
    end

    logger.debug "Saving backup to #{self.class.image_dir}"
    self.name = file.original_filename.remove(".tar.gz")

    if path.exist?
      errors.add(:filename, I18n.t(".invalid_filename_exists", scope: "backups.index"))
      return false
    end

    path.open("wb") do |f|
      f.write(file.read)
    end

    meta_file = data.join("meta.yml")
    unless meta_file.exist?
      errors.add(:file_content, I18n.t("backups.index.meta_missing"))
      path.delete
      return false
    end

    begin
      meta = YAML.load_file(meta_file)
    rescue Psych::SyntaxError
      errors.add(:file_content, I18n.t("backups.index.invalid_file_content"))
      path.delete
      return false
    end

    self.version = meta["version"].to_s
    self.size = path.size
    self.created_at = Time.zone.parse(meta["created_at"])
    # 20151222144602_create_backups.rb
    self.migration_level = meta["migration_level"] || 20151222144602
  end

  def delete_archive
    logger.debug "Deleting #{filename} from #{self.class.image_dir}"
    path.delete if path.exist?
  end

  def backup_version
    PlatformVersion.new(version)
  end

  def system_version
    PlatformVersion.new(ENV["CROWBAR_VERSION"])
  end

  def validate_chef_file_extension
    Dir.glob(data.join("knife", "**", "*")).each do |file|
      next if Pathname.new(file).directory?
      next if File.extname(file) == ".json"
      errors.add(:base, I18n.t("backups.validation.non_json_file"))
    end
  end

  def validate_version
    min_version = PlatformVersion.new("1.9")
    if backup_version < min_version
      errors.add(:base, I18n.t("backups.validation.version_too_low"))
    elsif backup_version > system_version
      errors.add(:base, I18n.t("backups.validation.version_too_high"))
    end
  end

  def validate_hostname
    backup_hostname = data.join("crowbar", "configs", "hostname").read.strip
    system_hostname = File.read("/etc/hostname").strip

    unless system_hostname == backup_hostname
      errors.add(:base, I18n.t("backups.validation.hostnames_not_identical"))
    end
  end

  def validate_upload_file_extension
    return if !file || (file && file.original_filename.match(/tar\.gz$/))

    errors.add(:base, I18n.t("backups.validation.invalid_file_extension"))
  end

  class << self
    def find_using_id_or_name(name)
      name = name.to_s

      if name =~ /\A\d+\Z/
        find_by(id: name.to_i)
      else
        find_by(name: name)
      end
    end

    def find_using_id_or_name!(name)
      find_using_id_or_name(name) || fail(ActiveRecord::RecordNotFound)
    end
  end
end
