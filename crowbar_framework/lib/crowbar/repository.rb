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

module Crowbar
  class Repository
    attr_reader :platform, :id, :config

    class << self
      def load!
        etc_yml = "/etc/crowbar/repos.yml"

        if Crowbar::Product.is_ses?
          @all_repos = YAML.load_file(Rails.root.join("config/repos-ses.yml"))
        else
          @all_repos = YAML.load_file(Rails.root.join("config/repos-cloud.yml"))
        end

        # merge data from etc config file
        etc_repos = {}
        if File.exist? etc_yml
          begin
            etc_repos = YAML.load_file(etc_yml)
          rescue SyntaxError
            # ok, let's live without it
          end
        end

        etc_repos.each do |platform, repos|
          if @all_repos.key? platform
            repos.each do |id, repo|
              # for repos that exist in our hard-coded file, we only allow
              # overwriting a subset of attributes
              if @all_repos[platform].key? id
                %w(url ask_on_error).each do |key|
                  @all_repos[platform][id][key] = repo[key] if repo.key? key
                end
              else
                @all_repos[platform][id] = repo
              end
            end
          else
            @all_repos[platform] = repos
          end
        end
      end

      def registry
        load! unless defined? @all_repos
        @all_repos
      end

      def where(options = {})
        platform = options.fetch :platform, nil
        repo = options.fetch :repo, nil
        check_all_repos.select do |r|
          if platform
            if repo
              r.platform == platform && r.id == repo
            else
              r.platform == platform
            end
          else
            r.id == repo
          end
        end
      end

      def all_platforms
        registry.keys
      end

      def repositories(platform)
        registry[platform].keys
      end

      def check_all_repos
        repochecks = []
        all_platforms.each do |platform|
          repositories(platform).each do |repo|
            repochecks << self.new(platform, repo)
          end
        end
        repochecks
      end

      def provided_and_enabled?(feature, platform = nil)
        answer = false

        if platform.nil?
          all_platforms.each do |p|
            if provided_and_enabled?(feature, p)
              answer = true
              break
            end
          end
        else
          found = false
          answer = true

          repositories(platform).each do |repo|
            provided_features = registry[platform][repo]["features"] || []

            next unless provided_features.include? feature
            found = true

            r = self.new(platform, repo)
            answer &&= r.active?
          end

          answer = false unless found
        end

        answer
      end

      def platform_available?(platform)
        available = true

        repositories(platform).each do |repo|
          r = self.new(platform, repo)

          next if r.required != "mandatory"
          next if r.active?

          available = false
          break
        end

        available
      end

      def disabled_platforms
        # forcefully reload the data, as we don't want to have outdated info
        # about what is mandatory or not
        load!
        all_platforms.reject { |platform| platform_available? platform }
      end

      def admin_ip
        NodeObject.admin_node.ip
      end

      def web_port
        Proposal.where(barclamp: "provisioner").first.raw_attributes["web_port"]
      end
    end

    def initialize(platform, repo)
      @platform = platform
      @id = repo
      @config = Repository.registry[@platform][@id]
    end

    def remote?
      !@config["url"].blank?
    end

    def available?
      remote? || (check_directory && check_repo_tag && check_key_file)
    end

    def exist?
      remote? || check_directory
    end

    def valid_repo?
      remote? || check_repo_tag
    end

    def valid_key_file?
      remote? || check_key_file
    end

    def name
      @config["name"] || @id
    end

    def required
      @config["required"] || "optional"
    end

    def url
      @config["url"] || \
        "http://#{Repository.admin_ip}:#{Repository.web_port}/#{@platform}/repos/#{@config["name"]}/"
    end

    def active?
      active_repos = Chef::DataBag.load("crowbar/repositories") rescue {}
      active_repos.fetch(@platform, {}).key? @id
    end

    def stale?
      active_repos = Chef::DataBag.load("crowbar/repositories") rescue {}
      if active_repos.fetch(@platform, {}).key? @id
        active_repos[@platform][@id] != to_databag_hash
      else
        false
      end
    end

    def to_databag_hash
      item = Hash.new
      item["name"] = name
      item["url"] = url
      item["ask_on_error"] = @config["ask_on_error"] || false
      item
    end

    private

    def repos_path
      Pathname.new(File.join("/srv/tftpboot", @platform, "repos"))
    end

    def repodata_path
      repos_path.join(@config["name"], "repodata")
    end

    def repodata_media_path
      repos_path.join(@config["name"], "suse", "repodata")
    end

    #
    # validation helpers
    #
    def check_directory
      repos_path.join(@config["name"]).directory?
    end

    def check_repo_tag
      expected = @config.fetch("repomd", {})["tag"]
      return true if expected.blank?

      repomd_path = repodata_path.join("repomd.xml")
      repomd_path = repodata_media_path.join("repomd.xml") unless repomd_path.file?

      if repomd_path.file?
        repo_tag = REXML::Document.new(repomd_path.open).root.elements["tags/repo"]
        if expected.is_a?(Array)
          !repo_tag.nil? && expected.include?(repo_tag.text)
        else
          !repo_tag.nil? && repo_tag.text == expected
        end
      else
        false
      end
    end

    def check_key_file
      expected = @config.fetch("repomd", {})["key_md5"]
      return true if expected.blank?

      key_path = repodata_path.join("repomd.xml.key")
      key_path = repodata_media_path.join("repomd.xml.key") unless key_path.file?

      if key_path.file?
        md5 = Digest::MD5.hexdigest(key_path.read)
        if expected.is_a?(Array)
          expected.include? md5
        else
          md5 == expected
        end
      else
        false
      end
    end
  end
end
