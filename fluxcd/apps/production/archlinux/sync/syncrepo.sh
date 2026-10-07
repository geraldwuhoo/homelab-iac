#!/bin/sh
#
# https://gitlab.archlinux.org/archlinux/infrastructure/-/blob/master/roles/syncrepo/files/syncrepo-template.sh
########
#
# Copyright © 2014-2019 Florian Pritz <bluewind@xinu.at>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, see <http://www.gnu.org/licenses/>.
#
########

set -e

target="/mnt/archlinux/mirror"
tmp="/mnt/archlinux/tmp"
bwlimit=16384
source_url='rsync://mirrors.mit.edu/archlinux/'
lastupdate_url='https://mirrors.mit.edu/archlinux/lastupdate'

mkdir -p "${target}" "${tmp}"

find "${target}" -name '.~tmp~' -exec rm -r {} +

rsync_cmd() {
	rsync -rtlH --safe-links --delete-after --timeout=600 --contimeout=60 -p \
		--delay-updates --no-motd --quiet "--temp-dir=${tmp}" "--bwlimit=${bwlimit}" "$@"
}

if [ -f "${target}/lastupdate" ] && [ "$(wget -qO- "${lastupdate_url}")" = "$(cat "${target}/lastupdate")" ]; then
	rsync_cmd "${source_url}/lastsync" "${target}/lastsync"
	echo "No changes upstream"
	exit 0
fi

rsync_cmd \
	--exclude='*.links.tar.gz*' \
	--exclude='/other' \
	--exclude='/sources' \
	"${source_url}" \
	"${target}"

echo "Last sync was $(date -d "@$(cat "${target}/lastsync")")"
