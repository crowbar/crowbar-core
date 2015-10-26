require "spec_helper"

describe Crowbar::Repository do
  before do
    Proposal.create!(barclamp: "provisioner", name: "test")
  end
  let!(:registry) { Crowbar::Repository.registry }

  describe "registry" do
    it "checks the registry" do
      expect(registry).to be_a(Hash)
    end
  end

  describe "class methods" do
    let(:platforms) { Crowbar::Repository.all_platforms }
    let(:check_all_repos) { Crowbar::Repository.check_all_repos }

    context "prepare repository check" do
      it "lists the available platforms" do
        expect(platforms).to be_an(Array)
      end

      it "lists all repositories for a given platform" do
        platforms.each do |platform|
          expect(Crowbar::Repository.repositories(platform)).to be_an(Array)
        end
      end
    end

    context "check all repositories" do
      it "validates the type returned by check_all_repos" do
        expect(check_all_repos).to be_an(Array)
      end

      it "validates the content of check_all_repos" do
        check_all_repos.each do |repo|
          expect(repo).to be_an_instance_of(Crowbar::Repository)
        end
      end
    end

    context "select specific repositories" do
      it "returns a list of repository objects" do
        platforms.each do |platform|
          Crowbar::Repository.repositories(platform).each do |repo|
            repo_objects = Crowbar::Repository.where(platform: platform, name: repo)
            expect(repo_objects).to be_an(Array)
          end
        end
      end

      it "validates the list of repository objects" do
        platforms.each do |platform|
          Crowbar::Repository.repositories(platform).each do |repo|
            repo_objects = Crowbar::Repository.where(platform: platform, name: repo)
            repo_objects.each do |repo_object|
              expect(repo_object).to be_an_instance_of(Crowbar::Repository)
            end
          end
        end
      end
    end
  end

  describe "performing repository checks" do
    let(:platform) { Crowbar::Repository.all_platforms.first }
    let(:repo_names) { Crowbar::Repository.repositories(platform) }
    let(:accessors) { [:platform, :id, :config] }
    let(:repository) { Crowbar::Repository.new(platform, repo_names.first) }

    context "creating a new Repository check" do
      it "returns the correct object" do
        expect(repository).to be_an_instance_of(Crowbar::Repository)
      end

      it "has accessable attributes" do
        accessors.each do |accessor|
          expect(repository).to respond_to(accessor)
        end
      end
    end
  end
end
