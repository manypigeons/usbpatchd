#!/bin/zsh

# Copyright 2022, Nick Botticelli. <nick.s.botticelli@gmail.com>
#  
# This file is part of usbpatchd.
# 
# usbpatchd is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# usbpatchd is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with usbpatchd. If not, see <https://www.gnu.org/licenses/>.

#
# usbpatchd
# install-usbpatchd.sh v0.1.0
#

# Fail-fast

#
# Patched by ManyPigeons
# This should work with SSHRD_Script.
# https://github.com/verygenericname/SSHRD_Script
#

set -e
set -u
set -o pipefail

ORIGINALPATH="$(pwd)"
SCRIPTPATH="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)"

SSH_PORT="4242"

function cleanup {
    cd "$ORIGINALPATH"
}

function SshCmd() {
    sshpass -p 'alpine' ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -p "$SSH_PORT" \
        root@localhost "$1"
}

function ScpUpload() {
    sshpass -p 'alpine' scp \
        -rP "$SSH_PORT" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$1" "root@localhost:$2"
}

function RemoteSnappyList() {
    SshCmd '/mnt1/usr/bin/snappy -f /mnt1 -l' | tr -d '\r'
}

function GetSystemSnapshot() {
    local snap=""

# please don't use snappy -s

    snap="$(
        RemoteSnappyList 2>/dev/null \
        | awk '$1 ~ /^com\.apple\.os\.update/ {print $1; exit}' \
        || true
    )"

    if [[ -n "$snap" ]]; then
        echo "$snap"
        return 0
    fi

    return 1
}

function OrigFsExists() {
    RemoteSnappyList 2>/dev/null \
    | awk '$1 == "orig-fs" {found=1} END {exit !found}'
}

function SnapshotExistsOnMnt1() {
    local target="$1"

    RemoteSnappyList 2>/dev/null \
    | awk -v snap="$target" '$1 == snap {found=1} END {exit !found}'
}

trap cleanup EXIT

cd "$SCRIPTPATH"

if ! [ -x "$(command -v sshpass)" ]; then
    echo 'sshpass is required but was not found.'
    echo 'Install it with: brew install esolitos/ipa/sshpass'
    exit 1
fi

if ! [ -x "$(command -v iproxy)" ]; then
    echo 'iproxy is required but was not found.'
    echo 'Install it with: brew install libusbmuxd'
    exit 1
fi

echo ''
echo 'Welcome to the usbpatchd installer!'
echo ''
echo 'You should now boot your SSH-capable ramdisk and mount the System volume.'
echo 'The System volume should be mounted at /mnt1.'
echo ''
echo "If you are using verygenericname's SSHRD_Script, follow the usage on github."
echo "https://github.com/verygenericname/SSHRD_Script"
echo ""
echo "If you're using SSHRD_Script, boot the ramdisk using:"
echo ""
echo "  sudo ./sshrd.sh <iOS version> (without <>)"
echo ""
echo "  sudo ./sshrd.sh boot"
echo ''
echo "If you're using SSHRD_Script, mount the volumes using:"
echo ""
echo "  sudo ./sshrd.sh ssh"
echo ''
echo '  mount_filesystems'
echo ''
echo 'Ensure to exit with "exit" after "mount_filesystems."'
echo ''
echo 'Finally, run iproxy in a new terminal with:'
echo '  iproxy 4242 22'
echo ''
echo 'You may need to replace 22 with 44 depending on your ramdisk.'
echo ''

printf 'Press Enter to continue...'
head -n 1 > /dev/null

echo 'Checking SSH connection...'
SshCmd 'echo SSH OK'

echo 'Checking that /mnt1 is mounted...'
if ! SshCmd 'test -d /mnt1/usr/bin'; then
    echo 'Error: /mnt1/usr/bin does not exist.'
    echo 'The System volume may not be mounted correctly at /mnt1.'
    echo ''
    echo 'Run mount_root on the ramdisk first, then try again.'
    exit 1
fi

echo 'Uploading snappy...'
ScpUpload 'root/usr/bin/snappy' '/mnt1/usr/bin/'

echo 'Making sure snappy is executable...'
SshCmd 'chmod +x /mnt1/usr/bin/snappy'

echo 'Current snapshots on /mnt1:'
RemoteSnappyList || true

echo ''
echo 'Checking for existing orig-fs snapshot...'

if OrigFsExists; then
    echo 'Snapshot orig-fs already exists.'
    echo 'Skipping snapshot rename.'
else
    echo 'Finding System snapshot on /mnt1...'

    if ! SYSTEM_SNAPSHOT="$(GetSystemSnapshot)"; then
        echo 'Unable to find a com.apple.os.update snapshot on /mnt1.'
        echo ''
        echo 'Debug info from snappy -f /mnt1 -l:'
        RemoteSnappyList || true
        exit 1
    fi

    SYSTEM_SNAPSHOT="$(echo "$SYSTEM_SNAPSHOT" | tr -d '\r\n')"

    echo "Snapshot detected on /mnt1: [$SYSTEM_SNAPSHOT]"

    if [[ -z "$SYSTEM_SNAPSHOT" ]]; then
        echo 'Error: snapshot name is empty.'
        echo 'Refusing to run fs_snapshot_rename with an empty source name.'
        exit 1
    fi

    if [[ "$SYSTEM_SNAPSHOT" != com.apple.os.update* ]]; then
        echo "Error: unexpected snapshot name: [$SYSTEM_SNAPSHOT]"
        echo 'Expected something beginning with com.apple.os.update'
        exit 1
    fi

    echo 'Verifying that the detected snapshot exists on /mnt1...'

    if ! SnapshotExistsOnMnt1 "$SYSTEM_SNAPSHOT"; then
        echo "Error: [$SYSTEM_SNAPSHOT] was not found in /mnt1’s actual snapshot list."
        echo ''
        echo 'Current snapshots on /mnt1:'
        RemoteSnappyList || true
        echo ''
        echo 'This usually means the System volume is mounted differently than expected,'
        echo 'or this iOS/device version does not match what this script expects.'
        exit 1
    fi

    echo "Renaming snapshot [$SYSTEM_SNAPSHOT] to [orig-fs]..."

    SshCmd "/mnt1/usr/bin/snappy -f /mnt1 -r \"$SYSTEM_SNAPSHOT\" -t orig-fs > /dev/null"

    echo 'Snapshot renamed successfully.'
fi

echo ''
echo 'Creating install archive...'
cd root
tar czf ../usbpatchd-install.tar.gz ./
cd ..

echo 'Uploading install archive...'
ScpUpload 'usbpatchd-install.tar.gz' '/mnt1/'

echo 'Extracting install archive on device...'
SshCmd 'cd /mnt1 && tar -xvzf usbpatchd-install.tar.gz && rm usbpatchd-install.tar.gz'

echo 'Fixing LaunchDaemon plist ownership...'
SshCmd '/usr/sbin/chown root:wheel /mnt1/Library/LaunchDaemons/com.apple.usbpatchd.plist'

echo ''
echo 'Finished installing usbpatchd.'
echo ''
echo 'Now you can reboot and run checkra1n, either from CLI or Recovery mode,'
echo 'to finish patching USB restriction.'
echo ''
echo 'After that, SSH should be accessible from the lock screen using:'
echo '  iproxy 2222 44'
