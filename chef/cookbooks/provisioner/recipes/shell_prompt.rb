# Copyright 2014, SUSE Linux GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

aliaz = begin
  display_alias = node["crowbar"]["display"]["alias"]
  if display_alias && !display_alias.empty?
    display_alias
  else
    node["hostname"]
  end
rescue
  node["hostname"]
end

%w(/etc/profile.d/zzz-prompt.sh /etc/profile.d/zzz-prompt.csh).each do |cfg|
  template cfg do
    source "zzz-prompt.sh.erb"
    owner "root"
    group "root"
    mode "0644"

    variables(
      prompt_from_template: proc { |user, cwd|
        node["provisioner"]["shell_prompt"].to_s \
          .gsub("USER", user) \
          .gsub("CWD", cwd) \
          .gsub("SUFFIX", "${prompt_suffix}") \
          .gsub("ALIAS", aliaz) \
          .gsub("HOST", node["hostname"]) \
          .gsub("FQDN", node["fqdn"])
      },

      zsh_prompt_from_template: proc {
        node["provisioner"]["shell_prompt"].to_s \
          .gsub("USER", "%{\\e[0;31m%}%n%{\\e[0m%}") \
          .gsub("CWD", "%{\\e[0;35m%}%~%{\\e[0m%}") \
          .gsub("SUFFIX", "%#") \
          .gsub("ALIAS", "%{\\e[0;35m%}#{aliaz}%{\\e[0m%}") \
          .gsub("HOST", "%{\\e[0;35m%}#{node["hostname"]}%{\\e[0m%}") \
          .gsub("FQDN", "%{\\e[0;35m%}#{node["fqdn"]}%{\\e[0m%}")
      },

      bash_prompt_from_template: proc {
        node["provisioner"]["shell_prompt"].to_s \
          .gsub("USER", "\\[\\e[01;31m\\]\\u\\[\\e[0m\\]") \
          .gsub("CWD", "\\[\\e[01;31m\\]\\w\\[\\e[0m\\]") \
          .gsub("SUFFIX", "${prompt_suffix}") \
          .gsub("ALIAS", "\\[\\e[01;35m\\]#{aliaz}\\[\\e[0m\\]") \
          .gsub("HOST", "\\[\\e[01;35m\\]#{node["hostname"]}\\[\\e[0m\\]") \
          .gsub("FQDN", "\\[\\e[01;35m\\]#{node["fqdn"]}\\[\\e[0m\\]")
      }
    )
  end
end
