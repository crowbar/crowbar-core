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

# Make sure /opt/dell/bin is in the path
if ! echo ${PATH} | /bin/grep -q /opt/dell/bin; then
    if [ $(/usr/bin/id -u) -eq 0 ]; then
        PATH=${PATH}:/opt/dell/bin
    fi
fi

# Make sure to export vars required by CLI
if [ -f /etc/crowbar.install.key ]; then
    export CROWBAR_KEY=$(cat /etc/crowbar.install.key)

    export CROWBAR_USERNAME=$(echo $CROWBAR_KEY | cut -d : -f 1)
    export CROWBAR_PASSWORD=$(echo $CROWBAR_KEY | cut -d : -f 2)
fi
