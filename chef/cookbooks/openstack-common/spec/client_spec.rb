# encoding: UTF-8
require_relative 'spec_helper'

describe 'openstack-common::client' do

  describe 'ubuntu' do

    let(:runner) { ChefSpec::Runner.new(UBUNTU_OPTS) }
    let(:node) { runner.node }
    let(:chef_run) do
      runner.converge(described_recipe)
    end

    it 'upgrades common client packages' do
      expect(chef_run).to upgrade_package('python-openstackclient')
    end
  end
end
