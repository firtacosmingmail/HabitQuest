#!/usr/bin/env bash
# CI only: check and install one App Store provisioning profile.
#
#   usage: ci_install_profile.sh <file.mobileprovision> <bundle id> <output prefix> [entitlement key ...]
#
# Fails unless the profile is a distribution (App Store) profile for exactly
# <TEAM_ID>.<bundle id> that carries every listed entitlement key. Installs it
# where Xcode looks for profiles and, when $GITHUB_OUTPUT is set, writes
# <prefix>_name=<profile Name> and <prefix>_uuid=<UUID> to it.
set -euo pipefail

PROFILE="${1:?usage: $0 <file.mobileprovision> <bundle id> <output prefix> [entitlement ...]}"
BUNDLE_ID="${2:?missing bundle id}"
PREFIX="${3:?missing output prefix}"
shift 3
TEAM_ID="${TEAM_ID:-9QMS59N2BZ}"

die() { echo "::error::$*" >&2; exit 1; }

PLIST="$(mktemp)"
trap 'rm -f "$PLIST"' EXIT
security cms -D -i "$PROFILE" > "$PLIST" || die "$PROFILE is not a valid provisioning profile"

pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }

NAME="$(pb Name)"
UUID="$(pb UUID)"
APP_ID="$(pb Entitlements:application-identifier)"
[ "$APP_ID" = "${TEAM_ID}.${BUNDLE_ID}" ] \
  || die "profile '$NAME' is for '$APP_ID', expected ${TEAM_ID}.${BUNDLE_ID}"
# Development and ad-hoc profiles list devices; App Store profiles do not.
if pb ProvisionedDevices > /dev/null; then
  die "profile '$NAME' lists devices: it is a development/ad-hoc profile, not App Store"
fi
[ "$(pb Entitlements:get-task-allow)" != "true" ] \
  || die "profile '$NAME' allows debugging (get-task-allow): not an App Store profile"
for key in "$@"; do
  pb "Entitlements:$key" > /dev/null \
    || die "profile '$NAME' ($BUNDLE_ID) lacks the '$key' entitlement: enable it on the App ID and regenerate the profile"
done

# Xcode < 16 reads the first directory, Xcode 16+ the second.
for dir in "$HOME/Library/MobileDevice/Provisioning Profiles" \
           "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  mkdir -p "$dir"
  cp "$PROFILE" "$dir/${UUID}.mobileprovision"
done
echo "Installed profile '$NAME' ($UUID) for $BUNDLE_ID"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "${PREFIX}_name=$NAME"
    echo "${PREFIX}_uuid=$UUID"
  } >> "$GITHUB_OUTPUT"
fi
