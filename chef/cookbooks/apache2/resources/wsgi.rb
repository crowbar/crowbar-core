actions :create, :delete
default_action :create

attribute :bind_host, kind_of: String, default: 'localhost'
attribute :bind_port, kind_of: Integer, default: 80
attribute :daemon_process, kind_of: String
attribute :user, kind_of: String
attribute :group, kind_of: String, default: nil
attribute :processes, kind_of: Integer, default: 3
attribute :threads, kind_of: Integer, default: 10
attribute :process_group, kind_of: String, default: nil
attribute :script_alias, kind_of: String, default: nil
attribute :directory, kind_of: String, default: nil
attribute :access_log, kind_of: String, default: nil
attribute :error_log, kind_of: String, default: nil

attr_accessor :exists
