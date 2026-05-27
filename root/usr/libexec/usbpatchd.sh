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
#

LOG_FILE="/private/var/mobile/Documents/usbpatchd.log"

function log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "usbpatchd starting..."

# Detect system volume disk identifier
SYSVOL="$(mount | awk '$3 == "/" {print $1; exit}')"

if [ -z "$SYSVOL" ]; then
    log "Error: could not detect system volume disk identifier."
    exit 1
fi

log "System volume detected at: $SYSVOL"

# Allow writing to System
if /sbin/mount -o rw,update -t apfs "$SYSVOL" /; then
    log "System volume remounted read-write successfully."
else
    log "Error: failed to remount system volume read-write."
    exit 1
fi

EFFECTIVE_PLIST="/private/var/mobile/Library/UserConfigurationProfiles/EffectiveUserSettings.plist"
PUBLIC_PLIST="/private/var/mobile/Library/UserConfigurationProfiles/PublicInfo/PublicEffectiveUserSettings.plist"

# Unlock files
if /usr/bin/chflags -R nouchg /private/var/mobile/Library/UserConfigurationProfiles; then
    log "Unlocked UserConfigurationProfiles successfully."
else
    log "Error: failed to unlock UserConfigurationProfiles."
    exit 1
fi

if [ -f "$EFFECTIVE_PLIST" ]; then
    if /usr/libexec/PlistBuddy -c \
        "Set :restrictedBool:allowUSBRestrictedMode:value false" \
        "$EFFECTIVE_PLIST"; then
        log "Patched EffectiveUserSettings.plist successfully."
    else
        log "Error: failed to patch EffectiveUserSettings.plist."
        exit 1
    fi
else
    log "Warning: EffectiveUserSettings.plist not found, skipping."
fi

if [ -f "$PUBLIC_PLIST" ]; then
    if /usr/libexec/PlistBuddy -c \
        "Set :restrictedBool:allowUSBRestrictedMode:value false" \
        "$PUBLIC_PLIST"; then
        log "Patched PublicEffectiveUserSettings.plist successfully."
    else
        log "Error: failed to patch PublicEffectiveUserSettings.plist."
        exit 1
    fi
else
    log "Warning: PublicEffectiveUserSettings.plist not found, skipping."
fi

if /usr/bin/chflags -R uchg /private/var/mobile/Library/UserConfigurationProfiles; then
    log "Re-locked UserConfigurationProfiles successfully."
else
    log "Error: failed to re-lock UserConfigurationProfiles."
    exit 1
fi

log "usbpatchd finished successfully."
