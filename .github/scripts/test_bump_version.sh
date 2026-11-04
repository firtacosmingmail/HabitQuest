#!/usr/bin/env bash
# Local tests for bump_version.sh. Each case works on a temporary copy of
# pubspec.yaml; the real file is never modified.
#   usage: .github/scripts/test_bump_version.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUMP="$HERE/bump_version.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "ok   - $1"; }
bad() { fail=$((fail + 1)); echo "FAIL - $1"; }

# expect_ok <name> <branch> <pubspec version line> <min build> <expected version>
expect_ok() {
  local name="$1" branch="$2" vline="$3" min="$4" want="$5" f out got
  f="$WORK/$name.yaml"
  sed "s/^version:.*/$vline/" "$ROOT/pubspec.yaml" > "$f"
  if out="$("$BUMP" "$branch" "$f" "$min" 2>&1)"; then
    got="$(grep -E '^version:' "$f")"
    if [ "$out" = "$want" ] && [ "$got" = "version: $want" ]; then
      # Only the version line may change.
      if [ "$(diff <(sed "s/^version:.*/$vline/" "$ROOT/pubspec.yaml") "$f" | grep -c '^[<>]')" = "2" ]; then
        ok "$name -> $want"
      else
        bad "$name: lines other than version changed"
      fi
    else
      bad "$name: stdout='$out' file='$got', want '$want'"
    fi
  else
    bad "$name: exited non-zero: $out"
  fi
}

# expect_fail <name> <branch> <pubspec version line or "-" to delete it> [min build]
expect_fail() {
  local name="$1" branch="$2" vline="$3" min="${4:-0}" f before out
  f="$WORK/$name.yaml"
  if [ "$vline" = "-" ]; then
    grep -vE '^version:' "$ROOT/pubspec.yaml" > "$f"
  else
    sed "s/^version:.*/$vline/" "$ROOT/pubspec.yaml" > "$f"
  fi
  before="$(cat "$f")"
  if out="$("$BUMP" "$branch" "$f" "$min" 2>&1)"; then
    bad "$name: expected failure, got '$out'"
  elif [ "$(cat "$f")" != "$before" ]; then
    bad "$name: failed but modified the file"
  else
    ok "$name rejected ($out)"
  fi
}

expect_ok   uppercase_V          release/V1.2.3            "version: 1.0.0+1"   0   "1.2.3+2"
expect_ok   lowercase_v          release/v1.2.3            "version: 1.0.0+1"   0   "1.2.3+2"
expect_ok   refs_prefix          refs/heads/release/V2.0.1 "version: 1.4.0+23"  0   "2.0.1+24"
expect_ok   run_number_wins      release/V1.2.3            "version: 1.0.0+1"   57  "1.2.3+57"
expect_ok   pubspec_wins         release/V1.2.3            "version: 1.0.0+80"  57  "1.2.3+81"
expect_ok   equal_min            release/V1.2.3            "version: 1.0.0+56"  57  "1.2.3+57"
expect_ok   same_version_rebuild release/V1.2.3            "version: 1.2.3+57"  57  "1.2.3+58"
expect_ok   zero_parts           release/V0.0.0            "version: 1.0.0+1"   0   "0.0.0+2"
expect_ok   multi_digit          release/V10.20.30         "version: 1.4.0+999" 0   "10.20.30+1000"
expect_ok   leading_zero_build   release/V1.5.0            "version: 1.4.0+09"  0   "1.5.0+10"
expect_ok   trailing_comment     release/V1.5.0            "version: 1.4.0+23 # bumped by CI" 0 "1.5.0+24"

expect_fail missing_build_number release/V1.5.0            "version: 1.4.0"
expect_fail missing_version_line release/V1.5.0            "-"
expect_fail garbage_build        release/V1.5.0            "version: 1.4.0+abc"
expect_fail bad_branch_prefix    feature/V1.5.0            "version: 1.4.0+23"
expect_fail releases_prefix      releases/V1.5.0           "version: 1.4.0+23"
expect_fail two_parts            release/V1.5              "version: 1.4.0+23"
expect_fail four_parts           release/V1.5.0.1          "version: 1.4.0+23"
expect_fail suffix               release/V1.5.0-rc1        "version: 1.4.0+23"
expect_fail leading_zero         release/V01.5.0           "version: 1.4.0+23"
expect_fail no_v                 release/1.5.0             "version: 1.4.0+23"
expect_fail other_letter         release/x1.5.0            "version: 1.4.0+23"
expect_fail space_in_name        "release/V1.5.0 "         "version: 1.4.0+23"
expect_fail empty_branch         ""                        "version: 1.4.0+23"
expect_fail bad_min_build        release/V1.5.0            "version: 1.4.0+23"  abc
expect_fail too_large            release/V1.5.0            "version: 1.4.0+23"  2100000000

# GITHUB_OUTPUT is filled in.
f="$WORK/gh_output.yaml"; o="$WORK/gh_output.txt"
sed "s/^version:.*/version: 1.4.0+23/" "$ROOT/pubspec.yaml" > "$f"
GITHUB_OUTPUT="$o" "$BUMP" release/V1.5.0 "$f" 30 > /dev/null
if [ "$(cat "$o")" = $'version=1.5.0+30\nversion_name=1.5.0\nbuild_number=30' ]; then
  ok "GITHUB_OUTPUT written"
else
  bad "GITHUB_OUTPUT: $(cat "$o")"
fi

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
