#!/bin/bash
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
# usbpatchd.sh v0.1.0
#

LOG_FILE="/tmp/usbpatchd.log"

function log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "usbpatchd starting..."

# Allow writing to System
log "Remounting system volume read-write..."
/sbin/mount -o rw,union,update -t apfs /dev/disk0s1s1 /
log "mount exited with code $?"

# Unlock files
log "Unlocking UserConfigurationProfiles..."
/usr/bin/chflags -R nouchg /private/var/mobile/Library/UserConfigurationProfiles
log "chflags nouchg exited with code $?"

# Patch USB restriction
log "Patching EffectiveUserSettings.plist..."
/usr/bin/plutil -key restrictedBool -key allowUSBRestrictedMode -dict -key value -0 /private/var/mobile/Library/UserConfigurationProfiles/EffectiveUserSettings.plist
log "plutil EffectiveUserSettings exited with code $?"

log "Patching PublicEffectiveUserSettings.plist..."
/usr/bin/plutil -key restrictedBool -key allowUSBRestrictedMode -dict -key value -0 /private/var/mobile/Library/UserConfigurationProfiles/PublicInfo/PublicEffectiveUserSettings.plist
log "plutil PublicEffectiveUserSettings exited with code $?"

# Lock files to prevent modification of USB restriction settings
log "Re-locking UserConfigurationProfiles..."
/usr/bin/chflags -R uchg /private/var/mobile/Library/UserConfigurationProfiles
log "chflags uchg exited with code $?"

log "usbpatchd finished."

log "Restarting lockdownd..."
/bin/launchctl stop com.apple.lockdownd
sleep 2
/bin/launchctl start com.apple.lockdownd
log "lockdownd restart exited with code $?"
