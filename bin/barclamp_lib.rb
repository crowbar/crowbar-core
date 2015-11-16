#
# Copyright 2011-2013, Dell
# Copyright 2013-2015, SUSE Linux GmbH
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

require "getoptlong"
require "active_support/all"

@hostname = ENV["CROWBAR_IP"] || "127.0.0.1"
@port = ENV["CROWBAR_PORT"] || 80

@debug = false
@allow_zero_args = false
@timeout = 500
@crowbar_key_file = "/etc/crowbar.install.key"

@data = ""

@mapped_commands = [
  "api_help",
  "transition",
  "show",
  "delete",
  "list",
  "elements",
  "element_node",
  "proposal"
]

@options = [
  [["--help", "-h", GetoptLong::NO_ARGUMENT], "--help or -h - help"],
  [["--username", "-U", GetoptLong::REQUIRED_ARGUMENT], "--username <username> or -U <username>  - specifies the username"],
  [["--password", "-P", GetoptLong::REQUIRED_ARGUMENT], "--password <password> or -P <password>  - specifies the password"],
  [["--hostname", "-n", GetoptLong::REQUIRED_ARGUMENT], "--hostname <name or ip> or -n <name or ip>  - specifies the destination server"],
  [["--port", "-p", GetoptLong::REQUIRED_ARGUMENT], "--port <port> or -p <port> - specifies the destination server port"],
  [["--debug", "-d", GetoptLong::NO_ARGUMENT], "--debug or -d - turns on debugging information"],
  [["--data", GetoptLong::REQUIRED_ARGUMENT], "--data <data> - used by create or edit as data (must be in json format)"],
  [["--file", GetoptLong::REQUIRED_ARGUMENT], "--file <file> - used by create or edit as data when read from a file (must be in json format)"],
  [["--timeout", GetoptLong::REQUIRED_ARGUMENT], "--timeout <seconds> - timeout in seconds for read http reads"]
]

@proposal_commands = {
  "list" => [
    "proposal_list",
    "list - show a list of current proposals"
  ],
  "create" => [
    "proposal_create ARGV.shift",
    "create <name> - create a proposal"
  ],
  "show" => [
    "proposal_show ARGV.shift",
    "show <name> - show a specific proposal"
  ],
  "edit" => [
    "proposal_edit ARGV.shift",
    "edit <name> - edit a new proposal"
  ],
  "delete" => [
    "proposal_delete ARGV.shift",
    "delete <name> - delete a proposal"
  ],
  "commit" => [
    "proposal_commit ARGV.shift",
    "commit <name> - Commit a proposal to active"
  ],
  "dequeue" => [
    "proposal_dequeue ARGV.shift",
    "dequeue <name> - Dequeue a proposal to active"
  ]
}

@commands = {
  "help" => [
    "usage 0",
    "help - this page"
  ],
  "api_help" => [
    "api_help",
    "crowbar API help - help for this barclamp."
  ],
  "list" => [
    "list",
    "list - show a list of current configs"
  ],
  "show" => [
    "show ARGV.shift",
    "show <name> - show a specific config"
  ],
  "delete" => [
    "delete ARGV.shift",
    "delete <name> - delete a config"
  ],
  "proposal" => [
    "run_sub_command(@proposal_commands, ARGV.shift)",
    "proposal - Proposal sub-commands",
    @proposal_commands
  ],
  "elements" => [
    "elements",
    "elements - List elements of a #{@barclamp} deploy"
  ],
  "element_node" => [
    "element_node ARGV.shift",
    "element_node <name> - List nodes that could be that element"
  ],
  "transition" => [
    "transition(ARGV.shift,ARGV.shift)",
    "transition <name> <state> - Transition machine named name to state"
  ]
}

def print_commands(cmds, spacer = "  ")
  cmds.each do |key, command|
    puts "#{spacer}#{command[1]}"
    print_commands(command[2], "  #{spacer}") if command[0] =~ /run_sub_command\(/
  end
end

def usage(rc)
  puts "Usage: crowbar #{@barclamp} [options] <subcommands>"
  @options.each do |options|
    puts "  #{options[1]}"
  end
  print_commands(@commands.sort)
  exit rc
end

def opt_parse
  get_user_password
  standard_opt_parse

  if ARGV.length == 0 and !@allow_zero_args
    usage -1
  end

  check_user_password
end

def get_user_password
  key = ENV["CROWBAR_KEY"]

  if key.nil? and ::File.exists?(@crowbar_key_file) and ::File.readable?(@crowbar_key_file)
    begin
      key = File.read(@crowbar_key_file).strip
    rescue => e
      warn "Unable to read crowbar key from #{@crowbar_key_file}: #{e}"
    end
  end

  if key
    @username, @password = key.split(":",2)
  end
end

def standard_opt_parse
  sub_options = @options.map { |x| x[0] }
  opts = GetoptLong.new(*sub_options)

  opts.each do |opt, arg|
    if ! parse_standard_opt(opt, arg)
      parse_extra_opt(opt, arg)
    end
  end
end

def parse_standard_opt(opt, arg)
  case opt
  when "--help"
    usage 0
  when "--debug"
    @debug = true
  when "--hostname"
    @hostname = arg
  when "--username"
    @username = arg
  when "--password"
    @password = arg
  when "--port"
    @port = arg.to_i
  when "--timeout"
    @timeout = arg.to_i
  when "--data"
    @data = arg
  when "--file"
    @data = File.read(arg)
  else
    return false
  end

  return true
end

def parse_extra_opt(opt, arg)
  found = false
  @options.each do |x|
    next unless x[0].include? opt
    x[2].call(opt, arg)
    found = true
  end
  usage(-1) unless found
end

def check_user_password
  if @username.nil? or @password.nil?
    STDERR.puts "CROWBAR_KEY not set, will not be able to authenticate!"
    STDERR.puts "Please set CROWBAR_KEY or use -U and -P"
    exit 1
  end
end

def deprecated_message(msg)
  if $stdout.tty?
    $stderr.puts "\e[31m#{msg}\e[0m"
  else
    $stderr.puts msg
  end
end

def deprecated_exec(*cmd)
  execute = [
    "crowbarctl"
  ].concat(
    cmd
  )

  if @username.present?
    execute.push "-U '#{@username}'"
  end

  if @password.present?
    execute.push "-P '#{@password}'"
  end

  if @timeout != 500
    execute.push "-t #{@timeout}"
  end

  if @hostname != "127.0.0.1" || @port != 80
    execute.push "-s 'http://#{@hostname}:#{@port}'"
  end

  if @username.empty? && @password.empty?
    execute.push "--anonymous"
  end

  if @debug
    execute.push "--debug"
  end

  deprecated_message <<-MSG.strip_heredoc
    This command is deprecated, please use:
    #{execute.join(" ")}
  MSG

  exec(execute.join(" "))
end

def run_sub_command(cmds, subcmd)
  if [
    "api_help",
    "transition",
    "show",
    "delete",
    "list",
    "elements",
    "element_node",
    "proposal"
  ].include?(subcmd)
    case subcmd
    when "api_help"
      res = deprecated_exec(
        "server",
        "api",
        @barclamp
      )
    when "transition"
      usage(-2) unless ARGV.length == 2

      res = deprecated_exec(
        "node",
        "transition",
        ARGV.shift,
        ARGV.shift
      )
    when "show"
      usage(-2) unless ARGV.length == 1

      res = deprecated_exec(
        "proposal",
        "show",
        @barclamp,
        ARGV.shift,
        "--format json"
      )
    when "delete"
      usage(-2) unless ARGV.length == 1

      res = deprecated_exec(
        "proposal",
        "delete",
        @barclamp,
        ARGV.shift
      )
    when "list"
      usage(-2) unless ARGV.length == 0

      res = deprecated_exec(
        "proposal",
        "list",
        @barclamp,
        "--format plain"
      )
    when "elements"
      usage(-2) unless ARGV.length == 0

      res = deprecated_exec(
        "role",
        "list",
        @barclamp,
        "--format plain"
      )
    when "element_node"
      usage(-2) unless ARGV.length == 1

      res = deprecated_exec(
        "role",
        "show",
        @barclamp,
        ARGV.shift,
        "--format plain"
      )
    when "proposal"
      sub = ARGV.shift

      case sub
      when "commit"
        args_count = 1
        args_append = ""
      when "dequeue"
        args_count = 1
        args_append = ""
      when "delete"
        args_count = 1
        args_append = ""
      when "create"
        args_count = 1
        args_append = ""

        args_append.push(
          @data
        ) if data.present?
      when "edit"
        args_count = 1
        args_append = ""

        args_append.push(
          @data
        ) if data.present?
      when "show"
        args_count = 1
        args_append = "--format json"
      when "list"
        args_count = 0
        args_append = "--format plain"
      else
        args_count = 1
        args_append = ""
      end

      usage(-2) unless ARGV.length == args_count

      res = deprecated_exec(
        "proposal",
        sub,
        @barclamp,
        *ARGV,
        args_append
      )
    end

    return [
      "",
      res || 1
    ]
  end

  cmd = cmds[subcmd]
  usage(-2) if cmd.nil?
  eval cmd[0]
end

def run_command
  run_sub_command(@commands, ARGV.shift)
end

def main
  opt_parse
  res = run_command
  puts res[0]
  exit res[1]
end
