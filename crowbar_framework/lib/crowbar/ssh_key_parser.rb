#
# Copyright 2020, SUSE
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

module Crowbar
  module SSHKeyParser
    # Splits authorized ssh key line into parts as described in
    # Returns [options, type, key, comment] (options and comment could be nil)
    # https://man.openbsd.org/sshd
    def split_key_line(line)
      line = line.clone
      res = []
      field = ""
      escape = false # was last char a backslash (so current one is escaped)?
      quotes = 0 # number of double quotes in current field
      type_found_at = nil # index of valid key type (if found)
      until line.empty?
        char = line.slice!(0)
        # count quotes for proper space handling
        quotes += 1 if char == "\"" && !escape
        # end of field, store and reset
        if char == " " && quotes.even?
          type_found_at = res.size if valid_key_types.include? field
          res.push(field) unless field.empty?
          field = ""
          quotes = 0
          # break parsing if we already have three fields (rest is comment)
          # OR we found a valid key type and one more field (the key)
          # this is equivalent to:
          # ... if res.size == 3 || \
          #        type_found_at && res.size == type_found_at + 2
          break if res.size == (type_found_at || 1) + 2
        else
          field += char
        end
        escape = char == "\\"
      end
      # take the rest as-is
      field += line
      field.strip!
      res.push(field) unless field.empty?

      # add missing options field
      res.unshift(nil) if type_found_at && type_found_at.zero?
      # add missing comment field
      res.push(nil) if res.size < 4
      res
    end

    ## Return valid key types
    def valid_key_types
      [
        "sk-ecdsa-sha2-nistp256@openssh.com",
        "ecdsa-sha2-nistp256",
        "ecdsa-sha2-nistp384",
        "ecdsa-sha2-nistp521",
        "sk-ssh-ed25519@openssh.com",
        "ssh-ed25519",
        "ssh-dss",
        "ssh-rsa"
      ]
    end
  end
end
