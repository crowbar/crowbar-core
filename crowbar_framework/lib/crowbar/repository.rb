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
    attr_reader :platform, :arch, :id, :config

    class << self
      def load!
        # reset other cached values
        @admin_ip = nil
        @web_port = nil

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
            loaded = YAML.load_file(etc_yml)
            raise SyntaxError unless loaded.is_a?(Hash)
            etc_repos = loaded
          rescue SyntaxError
            # ok, let's live without it
            Rails.logger.warn("Could not parse #{etc_yml}; not using locally defined repositories!")
          end
        end

        etc_repos.each do |platform, arches|
          if @all_repos.key? platform
            arches.each do |arch, repos|
              if @all_repos[platform].key? arch
                repos.each do |id, repo|
                  # for repos that exist in our hard-coded file, we only allow
                  # overwriting a subset of attributes
                  if @all_repos[platform][arch].key? id
                    %w(url priority ask_on_error).each do |key|
                      @all_repos[platform][arch][id][key] = repo[key] if repo.key? key
                    end
                  else
                    @all_repos[platform][arch][id] = repo
                  end
                end
              else
                @all_repos[platform][arch] = repos
              end
            end
          else
            @all_repos[platform] = arches
          end
        end
      end

      def registry
        load! unless defined? @all_repos
        @all_repos
      end

      def where(options = {})
        platform = options.fetch :platform, nil
        arch = options.fetch :arch, nil
        repo = options.fetch :repo, nil
        result = []

        [:id, :name].each do |attr|
          result = check_all_repos.select do |r|
            if platform && arch && repo
              r.platform == platform && r.arch == arch && r.send(attr) == repo
            elsif platform && arch
              r.platform == platform && r.arch == arch
            elsif platform && repo
              r.platform == platform && r.send(attr) == repo
            elsif platform
              r.platform == platform
            elsif arch && repo
              r.arch == arch && r.send(attr) == repo
            elsif arch
              r.arch == arch
            else
              r.send(attr) == repo
            end
          end
          break unless result.empty?
        end

        result
      end

      def all_platforms
        registry.keys
      end

      def arches(platform)
        registry.fetch(platform, {}).keys
      end

      def repositories(platform, arch)
        registry.fetch(platform, {}).fetch(arch, {}).keys
      end

      def check_all_repos
        repochecks = []
        all_platforms.each do |platform|
          arches(platform).each do |arch|
            repositories(platform, arch).each do |repo|
              repochecks << new(platform, arch, repo)
            end
          end
        end
        repochecks
      end

      def provided_and_enabled?(feature, platform = nil, arch = nil)
        provided_with_enabled(feature, platform, arch, true).first
      end

      def provided_and_enabled_with_repolist(feature, platform = nil, arch = nil)
        provided_with_enabled(feature, platform, arch, true)
      end

      def provided?(feature, platform = nil, arch = nil)
        provided_with_enabled(feature, platform, arch, false).first
      end

      def provided_with_repolist(feature, platform = nil, arch = nil)
        provided_with_enabled(feature, platform, arch, false)
      end

      def platform_available?(platform, arch)
        available = true

        repositories(platform, arch).each do |repo|
          r = new(platform, arch, repo)

          next if r.required != "mandatory"
          next if r.active?

          available = false
          break
        end

        available
      end

      def disabled_platforms(arch)
        # forcefully reload the data, as we don't want to have outdated info
        # about what is mandatory or not
        load!
        all_platforms.reject { |platform| platform_available?(platform, arch) }
      end

      def admin_ip
        @admin_ip ||= NodeObject.admin_node.ip
      end

      def web_port
        @web_port ||= Proposal.where(barclamp: "provisioner").first.raw_attributes["web_port"]
      end

      # workaround for Chef::DataBag.destroy not working
      def chef_data_bag_destroy(name)
        Chef::DataBag.chef_server_rest.delete_rest("data/#{name}")
      end

      private

      def provided_with_enabled(feature,
                                platform = nil,
                                arch = nil,
                                check_enabled = true,
                                repos = {})
        answer = false

        if platform.nil?
          all_platforms.each do |p|
            if provided_with_enabled(feature, p, arch, check_enabled, repos).first
              answer = true
              break
            end
          end
        elsif arch.nil?
          arches(platform).each do |a|
            if provided_with_enabled(feature, platform, a, check_enabled, repos).first
              answer = true
              break
            end
          end
        else
          found = false
          answer = true

          repositories(platform, arch).each do |repo|
            provided_features = registry[platform][arch][repo]["features"] || []

            next unless provided_features.include? feature
            found = true

            r = new(platform, arch, repo)

            answer &&= r.available?
            unless r.available?
              repos[:missing] ||= {}
              repos[:missing][r.arch.to_sym] ||= []
              unless repos[:missing][r.arch.to_sym].include?(r.name)
                repos[:missing][r.arch.to_sym].push(r.name)
              end
            end

            break unless check_enabled
            answer &&= r.active?
            next if r.active?

            repos[:inactive] ||= {}
            repos[:inactive][r.arch.to_sym] ||= []
            unless repos[:inactive][r.arch.to_sym].include?(r.name)
              repos[:inactive][r.arch.to_sym].push(r.name)
            end
          end

          answer = false unless found
        end

        [answer, repos]
      end
    end

    def initialize(platform, arch, repo, registered = true)
      @platform = platform
      @arch = arch
      @id = repo
      @config = registered ? registry_config : {}
      ensure_link_smt_path
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
        "http://#{Repository.admin_ip}:#{Repository.web_port}/#{@platform}/#{@arch}/repos/#{name}/"
    end

    def priority
      @config["priority"] || 99
    end

    def active?
      db = data_bag
      !db.nil? && db.include?(data_bag_item_name)
    end

    def stale?
      db_item = data_bag_item

      if db_item.nil?
        false
      else
        Repository.data_bag_item_to_hash(db_item) != to_databag.to_hash
      end
    end

    #
    # Helpers for data bag storage
    #

    def to_databag
      item = Chef::DataBagItem.new
      item.data_bag data_bag_name
      item["id"] = data_bag_item_name
      item["name"] = name
      item["url"] = url
      item["priority"] = priority
      item["ask_on_error"] = @config["ask_on_error"] || false
      item
    end

    def data_bag_name
      "repos-#{platform}-#{arch}".tr(".", "_")
    end

    def data_bag_item_name
      @id.tr(".", "_")
    end

    def data_bag(create_if_needed = false)
      db = begin
        Chef::DataBag.load(data_bag_name)
      rescue Net::HTTPServerException
        nil
      end

      if db.nil? && create_if_needed
        db = Chef::DataBag.new
        db.name data_bag_name
        db.save
      end

      db
    end

    def data_bag_item
      Chef::DataBagItem.load(data_bag_name, data_bag_item_name)
    rescue Net::HTTPServerException
      nil
    end

    def self.data_bag_item_to_hash(item = data_bag_item)
      hash = item.to_hash
      hash.delete("_rev")
      hash
    end

    private

    def repos_path
      Pathname.new("/srv/tftpboot").join(@platform, @arch, "repos")
    end

    def repo_path
      repos_path.join(name)
    end

    def smt_path
      unless @config["smt_path"].blank?
        Pathname.new("/srv/www/htdocs/repo").join(@config["smt_path"])
      end
    end

    def repodata_path
      repo_path.join("repodata")
    end

    def repodata_media_path
      repo_path.join("suse", "repodata")
    end

    def ensure_link_smt_path
      unless remote? || smt_path.nil? || repo_path.directory? || !smt_path.directory?
        system("sudo", "-i", "ln", "-s", smt_path.to_s, repo_path.to_s)
      end
    end

    def registry_config
      Repository.registry[@platform][@arch][@id]
    end

    #
    # validation helpers
    #
    def check_directory
      repo_path.directory?
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
      expected = @config.fetch("repomd", {})["fingerprint"]
      return true if expected.blank?

      key_path = repodata_path.join("repomd.xml.key")
      key_path = repodata_media_path.join("repomd.xml.key") unless key_path.file?

      if key_path.file?
        fingerprint = `LC_ALL=C gpg --with-fingerprint #{key_path}`.split(/\r?\n/)
        fingerprint.keep_if { |d| d =~ /fingerprint/ }
        return false if fingerprint.empty?
        fingerprint = fingerprint[0].split("=")
        return false if fingerprint.length != 2
        fingerprint = fingerprint[1].split.join(" ")
        if expected.is_a?(Array)
          expected.include? fingerprint
        else
          fingerprint == expected
        end
      else
        false
      end
    end
  end
end
