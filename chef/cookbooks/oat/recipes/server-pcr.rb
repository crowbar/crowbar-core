#this part should be executed after pcr.rb gathered all clients pcrs

ruby_block "fill_oat_wl" do
block do
#prepare url
server = search(:node, "roles:oat-server") || []
address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(server.first, "admin").address
#address=server.first.fqdn
url = "http#{"s"if node[:inteltxt][:server][:secure]}://#{address}:#{node[:inteltxt][:server][:port]}"
#configure OATClient

#search all agents
agents = search(:node, "recipes:oat\\:\\:client") || []
if agents.size > 0
OATClient::config url, node[:inteltxt][:server][:secret], retries: 5, wait: 2
end

agents.each do |agent|
  if agent[:inteltxt][:pcr].size == 0
    next
  end
  #add all the agents into oat
  # TODO: (eshurmin@mirantis.com) agent[:name] is empty but must be contain correct name
  agent_name = agent[:hostname] || "unknown"
  oem_name="#{agent_name}-oem"
  oem_description="#{agent_name} #{agent[:dmi][:base_board][:product_name]} #{agent[:dmi][:base_board][:serial_number]} generated by crowbar"
  ##############reg oem here############
  oem_t = {
      name: oem_name,
      description: oem_description
  }
  oem = OATClient::OEM.new(oem_t)
  if oem.exists?
    Chef::Log.info("OEM #{oem_name} already exists")
  else
    Chef::Log.info("OEM #{oem_name} has been created") if oem.save
  end

  os_name="#{agent_name}-os"
  os_version="#{agent[:lsb][:release]}"
  os_description="#{agent_name} #{agent[:lsb][:description]}"
  ##############reg os here############
  os_t = {
      name: os_name,
      description: os_description,
      version: os_version
  }
  os = OATClient::OS.new(os_t)
  if os.exists?
    Chef::Log.info("OS #{os_name} #{os_version} already exists")
  else
    Chef::Log.info("OS #{os_name} #{os_version} has been created") if os.save
  end

  mle_oem_name="#{agent_name}-mle-oem"
  mle_oem_version="1" #we dont want to up version automaticaly or provide any interface to do it, it should be done manualy
  mle_oem_attestation_type="PCR"
  mle_oem_type="BIOS"
  mle_oem_description="#{agent_name} BIOS mle generated by crowbar"
  ##############reg oem mle here############
  mle_oem_t = {
      name: mle_oem_name,
      version: mle_oem_version,
      attestation_type: mle_oem_attestation_type,
      mle_type: mle_oem_type,
      description: mle_oem_description,
      oem_name: oem_name
  }
  mle_oem = OATClient::MLE.new(mle_oem_t)
  if mle_oem.exists?
    Chef::Log.info("MLE #{mle_oem_type} #{mle_oem_name} #{mle_oem_version} already exists")
  else
    (0..7).each do |n|
      #####whitelist pcr with mle_oem_name mle_oem_version oem_name#####
      mle_oem.add_manifest(name: n.to_s, value: agent[:inteltxt][:pcr][n.to_s].strip)
      Chef::Log.info("PCR #{n} for MLE #{mle_oem_type} #{mle_oem_name} #{mle_oem_version} has been added")
    end
    Chef::Log.info("MLE #{mle_oem_type} #{mle_oem_name} #{mle_oem_version} has been created") if mle_oem.save
  end

  mle_vmm_name="#{agent_name}-vmm-oem"
  mle_vmm_version="1"
  mle_vmm_attestation_type="PCR"
  mle_vmm_type="VMM"
  mle_vmm_description="#{agent_name} #{agent[:kernel][:release]} VMM mle generated by crowbar"
  ##############reg vmm mle here############
  mle_vmm_t = {
      name: mle_vmm_name,
      version: mle_vmm_version,
      attestation_type: mle_vmm_attestation_type,
      mle_type: mle_vmm_type,
      description: mle_vmm_description.gsub(/[#:]/,"_"),
      os_name: os_name,
      os_version: os_version
  }
  mle_vmm = OATClient::MLE.new(mle_vmm_t)
  if mle_vmm.exists?
    Chef::Log.info("MLE #{mle_vmm_type} #{mle_vmm_name} #{mle_vmm_version} already exists")
  else

    (17..19).each do |n|
      mle_vmm.add_manifest(name: n.to_s, value: agent[:inteltxt][:pcr][n.to_s].strip)
      Chef::Log.info("PCR #{n} for MLE #{mle_vmm_type} #{mle_vmm_name} #{mle_vmm_version} has been added")
    end
    Chef::Log.info("MLE #{mle_vmm_type} #{mle_vmm_name} #{mle_vmm_version} has been created") if mle_vmm.save
  end

  host_name="#{agent_name}"
  host_ip="#{agent[:crowbar][:network][:admin][:address]}"
  host_port="12345" #seems deprecated, used only with active polling
  host_description="#{agent_name} host generated by crowbar"
  ##############reg host here############
  host_t = {
      host_name: host_name,
      ip_address: host_ip,
      port: host_port,
      bios_name: mle_oem_name,
      bios_version: mle_oem_version,
      bios_oem: oem_name,
      vmm_name: mle_vmm_name,
      vmm_version: mle_vmm_version,
      vmm_os_name: os_name,
      vmm_os_version: os_version,
      email: nil,
      addon_sonnection_string: nil,
      description: host_description.gsub(/[#:]/,"_")
  }
  host = OATClient::Host.new(host_t)
  if host.exists?
    Chef::Log.info("Host #{host_name} #{host_ip}:#{host_port} already exists")
  else
    Chef::Log.info("Host #{host_name} #{host_ip}:#{host_port} has been created") if host.save
  end
end
end
action :create
end
