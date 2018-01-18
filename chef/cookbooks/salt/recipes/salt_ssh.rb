# requires repos
# http://download.nue.suse.com/ibs/SUSE/Products/SLE-Module-Adv-Systems-Management/12/x86_64/product/
# http://download.nue.suse.com/ibs/SUSE/Updates/SLE-Module-Adv-Systems-Management/12/x86_64/update/
package "salt-ssh" do
  action :install
end

nodes = node_search_with_cache("roles:dns-client OR roles:dns-server")
roster = []
nodes.each do |n|
  base_name_no_net = n[:fqdn].chomp(".#{n[:dns][:domain]}")
  nalias = n["crowbar"]["display"]["alias"] rescue nil
  nalias = base_name_no_net unless nalias && !nalias.empty?
  node_admin_ip = Barclamp::Inventory.get_network_by_type(n, "admin").address
  roster.push(
    fqdn: n[:fqdn],
    ip: node_admin_ip,
    roles: n.roles,
    alias: nalias
  )
end
roster.sort_by! { |n| n[:alias] }

# Rewrite our roster file
template "/etc/salt/roster" do
  source "roster.erb"
  mode 0o644
  owner "root"
  group "root"
  variables(roster: roster)
end

template "/srv/pillar/roles.sls" do
  source "pillar-roles.erb"
  mode 0o644
  owner "root"
  group "root"
  variables(roster: roster)
end

directory "/etc/salt/pki/master/ssh" do
  owner "root"
  group "root"
  mode 0o755
  action :create
end

link "/etc/salt/pki/master/ssh/salt-ssh.rsa" do
  to "/root/.ssh/id_rsa"
end

link "/etc/salt/pki/master/ssh/salt-ssh.rsa.pub" do
  to "/root/.ssh/id_rsa.pub"
end
