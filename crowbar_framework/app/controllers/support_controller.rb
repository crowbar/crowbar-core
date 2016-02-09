#
# Copyright 2011-2013, Dell
# Copyright 2013-2014, SUSE LINUX Products GmbH
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

require "chef"

class SupportController < ApplicationController
  def logs
    filename = "crowbar-logs-#{Time.now.strftime("%Y%m%d-%H%M%S")}.tar.bz2"
    system("sudo", "-i", Rails.root.join("..", "bin", "gather_logs.sh").expand_path.to_s, filename)
    redirect_to "/export/#{filename}"
  end

  def index
    @export = default_export_hash
    export_dir.children.each do |file|
      filename = file.basename.to_s

      if filename =~ /^\./
        next
      elsif filename =~ /^(KEEP_THIS.*)|(index.html)/
        next
      elsif filename =~ /^crowbar-logs-.*/
        @export.files.logs.push filename
      elsif filename =~ /^crowbar-chef-.*/
        @export.files.chef.push filename
      elsif filename =~ /(.*).import.log$/
        @export.files.bc_import.push filename
      elsif filename =~ /^supportconfig.*/
        @export.files.support_configs.push filename
      else
        @export.files.other.push filename
      end

      @export.waiting = false if filename == @export.current
      @export.counter += 1
    end

    respond_to do |format|
      format.html
      format.json { render json: @export.to_json }
    end
  end

  def destroy
    file = check_dir("export").join(params[:id])

    begin
      file.unlink
      flash[:notice] = t("support.index.delete_succeeded", file: file.basename)
    rescue
      flash[:alert] = t("support.index.delete_failed", file: file.basename)
    end

    redirect_to utils_url
  end

  def export_supportconfig
    begin
      base = "supportconfig-#{Time.now.strftime("%Y%m%d-%H%M%S")}"
      filename = "#{base}.tbz"

      pid = Process.fork do
        begin
          tmp = Rails.root.join("tmp", base).to_s

          supportconfig = ["sudo", "-i", "supportconfig", "-Q", "-R", tmp]
          chown = ["sudo", "-i", "chown", "-R", "#{Process.uid}:#{Process.gid}", tmp]

          ok  = system(*supportconfig)
          ok &= system(*chown)

          tarball = Dir.glob("#{tmp}/*.tbz").first
          File.rename tarball, export_dir.join(filename) if tarball && ok
        rescue => e
          Rails.logger.warn(e.message)
        ensure
          FileUtils.rm_rf(tmp)
        end
      end

      Process.detach(pid)
      redirect_to utils_url(waiting: true, file: filename) and return
    rescue StandardError => e
      flash[:alert] = t("support.export.fail", error: e.message)
    end

    redirect_to utils_url
  end

  def export_chef
    begin
      filename = "crowbar-chef-#{Time.now.strftime("%Y%m%d-%H%M%S")}.tgz"

      tmpdir = Dir.mktmpdir
      tmpdirpath = Pathname.new(tmpdir)
      tmpfile_path = tmpdirpath.join(filename)

      begin
        NodeObject.all.each { |n| n.export(tmpdirpath) }
        RoleObject.all.each { |r| r.export(tmpdirpath) }
        Proposal.all.each { |p| p.export(tmpdirpath) }
      rescue StandardError => e
        FileUtils.remove_entry_secure tmpdir
        raise e
      end

      pid = Process.fork do
        begin
          cmd = ["tar", "czf", tmpfile_path.to_s, "*"]
          _stdout, ok = Open3.capture2(*cmd, chdir: tmpdir)
          File.rename(tmpfile_path, export_dir.join(filename)) if ok
        ensure
          FileUtils.remove_entry tmpdir
        end
      end

      Process.detach(pid)
      redirect_to utils_url(waiting: true, file: filename) and return
    rescue StandardError => e
      flash[:alert] = I18n.t("support.export.fail", error: e.message)
    end

    redirect_to utils_url
  end

  protected

  def default_export_hash
    Utils::ExtendedHash.new({
      waiting: params[:waiting] == "true" || params[:format] == "json",
      counter: 0,
      current: params["file"].to_s.gsub("-DOT-", "."),
      files: {
        logs: [],
        chef: [],
        other: [],
        support_configs: [],
        bc_import: []
      }
    })
  end

  def import_dir
    check_dir "import"
  end

  def export_dir
    check_dir "export"
  end

  def check_dir(type)
    path = Rails.root.join("public", type)

    unless path.directory?
      FileUtil.mkdir_p path.expand_path
    end

    path
  end
end
