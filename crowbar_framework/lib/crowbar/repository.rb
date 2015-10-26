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
    attr_reader :platform, :id, :registry

    class << self
      def load!
        @config = YAML.load_file(Rails.root.join("config/repos.yml"))
      end

      def registry
        load! unless defined? @config
        @config
      end

      def where(options = {})
        platform = options.fetch :platform, nil
        repo = options.fetch :repo, nil
        check_all_repos.select do |r|
          if platform
            if repo
              r.platform == platform && r.registry["name"] == repo
            else
              r.platform == platform
            end
          else
            r.registry["name"] == repo
          end
        end
      end

      def all_platforms
        registry.keys
      end

      def check_all_repos
        repochecks = []
        all_platforms.each do |platform|
          repositories(platform).each do |repo|
            check = self.new(platform, repo)
            if platform != Crowbar::Product.ses_platform && Crowbar::Product.is_ses?
              #FIXME skip the repo check until SES is ported to SLE12-SP1
              check.registry["required"] = "optional"
            end
            repochecks << check
          end
        end
        repochecks
      end

      def admin_platform
        NodeObject.admin_node.target_platform
      end

      def web_port
        Proposal.where(barclamp: "provisioner").first.raw_attributes["web_port"]
      end

      def repositories(platform)
        registry[platform]["repos"].keys
      end

      def admin_ip
        NodeObject.admin_node.ip
      end
    end

    def initialize(platform, repo)
      @platform = platform
      @id = repo
      @registry = Repository.registry[@platform]["repos"][@id]
      @url = url
    end

    def available?
      all_repo_dirs.include?(@registry["name"]) && check_repo_tag
    end

    def valid_key_file?
      if File.exist?(repomd_key_path)
        md5 = Digest::MD5.hexdigest(File.read(repomd_key_path))
        repomd_key_md5 == md5
      else
        false
      end
    end

    def repodata_path
      "/srv/tftpboot/#{@platform}/repos/#{@registry['name']}/repodata"
    end

    def repomd_key_md5
      @registry["repomd"]["md5"]
    end

    def repomd_key_path
      @registry["repomd"]["key"] || "#{repodata_path}/repomd.xml.key"
    end

    def url
      @registry["url"] || \
        "http://#{Repository.admin_ip}:#{Repository.web_port}/#{@platform}/repos/#{@registry['name']}"
    end

    def active?
      !bag_item.nil?
    end

    def to_databag!
      repository_item = Chef::DataBagItem.new
      repository_item.data_bag "repositories"
      repository_item["id"] = @id
      repository_item["platform"] = @platform
      repository_item["name"] = @registry["name"]
      repository_item["url"] = url
      repository_item["ask_on_error"] = @registry["ask_on_error"] || false
      repository_item["product_name"] = @registry["product_name"]
      repository_item
    end

    def bag_item
      Chef::DataBagItem.load("repositories", @id) rescue nil
    end

    private

    #
    # validation helpers
    #
    def all_repo_dirs
      path = File.join("/srv/tftpboot", @platform, "repos")
      Dir["#{path}/*"].map { |p| p.split("/").last }
    end

    def check_repo_tag
      expected = @registry["repomd"]["tag"]
      repomd_path = "#{repodata_path}/repomd.xml"
      if File.exist?(repomd_path)
        REXML::Document.new(File.open(repomd_path)).root.elements["tags/repo"].text == expected
      else
        false
      end
    end
  end
end
