#!/usr/bin/env bash
# Set pubspec.yaml's version for a release branch.
#
#   usage: bump_version.sh <branch> [pubspec.yaml] [min build number]
#
# <branch> must be "release/VX.Y.Z" or "release/vX.Y.Z" (an optional
# "refs/heads/" prefix is accepted). The "version: A.B.C+N" line in
# pubspec.yaml is rewritten to "version: X.Y.Z+B" where
#
#   B = max(N + 1, <min build number>)
#
# CI passes github.run_number as the minimum, so the build number always goes
# up: past the one in pubspec (never reused, which Play and App Store Connect
# both reject) and past every earlier release run, even when two release
# branches start from the same pubspec. The version name (X.Y.Z) is used for
# both Android (versionName) and iOS (CFBundleShortVersionString); the build
# number for versionCode and CFBundleVersion.
#
# Prints the new version on stdout. When $GITHUB_OUTPUT is set, it also writes
# version=, version_name= and build_number= to it.
# Exits non-zero (and leaves the file untouched) on any invalid input.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

BRANCH="${1:-}"
PUBSPEC="${2:-pubspec.yaml}"
MIN_BUILD="${3:-0}"
[ -n "$BRANCH" ] || die "usage: $0 <release/VX.Y.Z branch> [pubspec.yaml] [min build]"
BRANCH="${BRANCH#refs/heads/}"
[[ "$MIN_BUILD" =~ ^[0-9]+$ ]] || die "min build number '$MIN_BUILD' is not a number"

# X.Y.Z, no leading zeros (except a bare 0), nothing before or after.
SEMVER_RE='^release/[Vv](0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
[[ "$BRANCH" =~ $SEMVER_RE ]] || die "branch '$BRANCH' is not a release branch: expected release/VX.Y.Z (e.g. release/V1.2.3)"
VERSION_NAME="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"

[ -f "$PUBSPEC" ] || die "$PUBSPEC not found"

count="$(grep -cE '^version:' "$PUBSPEC" || true)"
[ "$count" = "1" ] || die "expected exactly one top-level 'version:' line in $PUBSPEC, found $count"

line="$(grep -E '^version:' "$PUBSPEC")"
LINE_RE='^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)[[:space:]]*(#.*)?$'
[[ "$line" =~ $LINE_RE ]] || die "cannot read a build number from '$line' (expected version: A.B.C+N)"
CURRENT_BUILD="${BASH_REMATCH[1]}"

NEW_BUILD=$((10#$CURRENT_BUILD + 1))
if [ $((10#$MIN_BUILD)) -gt "$NEW_BUILD" ]; then
  NEW_BUILD=$((10#$MIN_BUILD))
fi
# Android's versionCode must stay below 2100000000.
[ "$NEW_BUILD" -lt 2100000000 ] || die "build number $NEW_BUILD is too large for Android"
NEW_VERSION="${VERSION_NAME}+${NEW_BUILD}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
awk -v v="$NEW_VERSION" '
  /^version:/ { print "version: " v; next }
  { print }
' "$PUBSPEC" > "$tmp"
cat "$tmp" > "$PUBSPEC"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=$NEW_VERSION"
    echo "version_name=$VERSION_NAME"
    echo "build_number=$NEW_BUILD"
  } >> "$GITHUB_OUTPUT"
fi

echo "$NEW_VERSION"
