#!/bin/bash
#
# Copyright 2011-2013, Dell
# Copyright 2013-2014, SUSE LINUX Products GmbH
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

mkdir -p /tmp/crowbar-logs
tarname="${1-$(date '+%Y%m%d-%H%M%S')}"
targetdir="/opt/dell/crowbar_framework/public/export"
sort_by_last() {
    local src=() keys=() sorted=() line=""
    while read line; do
	[[ $line && $line != '.' && $line != '..' ]] || continue
	src+=("$line");
	keys+=("${line##*/}")
    done
    while read line; do
	echo "${src[$line]}" |tee -a "$targetdir/debug.log"
    done < <( (for i in "${!keys[@]}"; do
	    echo "$i ${keys[$i]}"; done) | \
	sort -k 2 | \
	cut -d ' ' -f 1)
}


(   flock -s 200
    logdir=$(mktemp -d "/tmp/crowbar-logs/$tarname-XXXXX")
    mkdir -p "$logdir"
    mkdir -p "$targetdir"
    cd "$logdir"
    sshopts=(-q -o 'StrictHostKeyChecking no'
	-o 'UserKnownHostsFile /dev/null')
    logs=(/var/log /etc)
    logs+=(/var/chef/cache /var/cache/chef /opt/dell/crowbar_framework/db)

    mkdir nodes
    for node in $(crowbarctl node list --no-verify-ssl --no-meta --plain); do
        crowbarctl node show $node --no-verify-ssl --json > nodes/$node.json
    done

    mkdir proposals
    for barclamp in $(crowbarctl barclamp list --no-verify-ssl --plain); do
        for proposal in $(crowbarctl proposal list $barclamp --no-verify-ssl --plain); do
            crowbarctl proposal show $barclamp $proposal --no-verify-ssl --json > proposals/$barclamp-$proposal.json
        done
    done

    mkdir roles
    for role in $(sudo -H knife role list | grep '\-config-'); do
        knife role show -F json $role > roles/$role.json
    done

    for node in $(sudo -H knife node list); do
	tarfile="${node%%.*}-${tarname}.tar.gz"
	(   sudo ssh "${sshopts[@]}" "${node}" \
		tar czf - "${logs[@]}" > "${tarfile}"
	)&
    done &>/dev/null
    wait
    cd ..
    find . -depth -print | \
	sort_by_last / | \
	cpio -o -H ustar | \
	bzip2 -9 > "/tmp/${tarname}"
	  mv "/tmp/${tarname}" "$targetdir/${tarname}"
    rm -rf "$logdir"
) 200>/tmp/crowbar-logs/.lock
