#!/usr/bin/env bash
# CI only: switch one target's *Release* build configuration to manual
# App Store signing, in place, on the CI checkout. Never commit the result:
# local Release builds (flutter run --release) keep using automatic signing.
#
# The release workflow runs it twice, once per signed target:
#   ios/scripts/ci_manual_signing.sh Runner            "<Runner profile name>"
#   ios/scripts/ci_manual_signing.sh HabitQuestWidgets "<widget profile name>"
#
# Why patch instead of passing xcodebuild overrides: `flutter build ipa` has no
# way to forward build settings, and a command-line override such as
# PROVISIONING_PROFILE_SPECIFIER would hit every target (Pods, and the widget
# extension, which needs its own profile), which then fail to sign.
#
# Usage: ios/scripts/ci_manual_signing.sh <target> "<provisioning profile name>" [pbxproj path]
set -euo pipefail

TARGET="${1:?usage: $0 <target> <provisioning profile name> [pbxproj]}"
PROFILE_NAME="${2:?usage: $0 <target> <provisioning profile name> [pbxproj]}"
PBXPROJ="${3:-$(cd "$(dirname "$0")/.." && pwd)/Runner.xcodeproj/project.pbxproj}"
TEAM_ID="${TEAM_ID:-9QMS59N2BZ}"
IDENTITY="${CODE_SIGN_IDENTITY:-Apple Distribution}"

# Resolve the Release config ID from the target's configuration list.
CONFIG_ID="$(TARGET="$TARGET" awk '
  index($0, "Build configuration list for PBXNativeTarget \"" ENVIRON["TARGET"] "\" */ = {") { inlist = 1 }
  inlist && /\/\* Release \*\/,/ { print $1; exit }
  inlist && /^\t\t\};/ { inlist = 0 }
' "$PBXPROJ")"
[ -n "$CONFIG_ID" ] || { echo "error: $TARGET Release configuration not found in $PBXPROJ" >&2; exit 1; }

PROFILE_NAME="$PROFILE_NAME" TEAM_ID="$TEAM_ID" IDENTITY="$IDENTITY" CONFIG_ID="$CONFIG_ID" \
perl -0pi -e '
  my ($id, $p, $t, $i) = @ENV{qw(CONFIG_ID PROFILE_NAME TEAM_ID IDENTITY)};
  s{(\t\t\Q$id\E /\* Release \*/ = \{.*?\n\t\t\};)}{
    my $b = $1;
    $b =~ s/^\t\t\t\tCODE_SIGN_STYLE = .*?;\n//mg;
    $b =~ s/^\t\t\t\tCODE_SIGN_IDENTITY = .*?;\n//mg;
    $b =~ s/^\t\t\t\t"CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]" = .*?;\n//mg;
    $b =~ s/^\t\t\t\tDEVELOPMENT_TEAM = .*?;\n//mg;
    $b =~ s/^\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = .*?;\n//mg;
    $b =~ s/(buildSettings = \{\n)/$1\t\t\t\tCODE_SIGN_IDENTITY = "$i";\n\t\t\t\t"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "$i";\n\t\t\t\tCODE_SIGN_STYLE = Manual;\n\t\t\t\tDEVELOPMENT_TEAM = $t;\n\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "$p";\n/;
    $b;
  }se or die "Release block $id not found\n";
' "$PBXPROJ"

echo "$TARGET/Release ($CONFIG_ID): CODE_SIGN_STYLE=Manual, team $TEAM_ID, identity \"$IDENTITY\", profile \"$PROFILE_NAME\""
