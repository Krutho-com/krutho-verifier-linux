#!/usr/bin/env bash
#
# verify-release.sh: verify a downloaded Krutho verifier release.
#
# This script performs the steps in VERIFY.md and stops at the first failure.
# It exits 0 only if every check passed. Read VERIFY.md for what each check
# means and what the checks do not cover.
#
# Usage:
#   verify-release.sh -r RELEASE_DIR -k KEYS_DIR -a ALLOWED_SIGNERS [-p NAME=SHA256]...
#
# Options:
#   -r RELEASE_DIR      Directory holding the downloaded release files: the four
#                       files (NOTICES.md, krutho_verifier.h and the two .so
#                       files), SHA256SUMS and SHA256SUMS.sig.
#   -k KEYS_DIR         The KEYS directory from the current main of
#                       https://github.com/Krutho-com/krutho-sdk-swift. It must
#                       hold release-root.pub, revocation.txt,
#                       revocation.txt.sig and revoked.krl.
#   -a ALLOWED_SIGNERS  Your pinned allowed_signers file. It must hold exactly
#                       the one line pinned in VERIFY.md and nothing else.
#   -p NAME=SHA256      The SHA-256 of one release file, taken from your own
#                       pinned source (step 6 of VERIFY.md). NAME is one of the
#                       four file names. SHA256 is 64 lowercase hex characters.
#                       Repeat -p for each file you use. Without -p, the script
#                       cannot tell which version the files belong to, and it
#                       says so.
#   -h                  Print this help.
#
# Exit status:
#   0  every check passed
#   1  a check failed (the message on stderr names the step and the cause)
#   2  bad usage, or a required tool is missing
#
# Tools: ssh-keygen (OpenSSH with `-Y verify -r`), sha256sum or shasum -a 256,
# date, awk, grep, sort, diff, cut, sed, mktemp. Works with bash 3.2 or later.
# The script only reads its inputs. It writes to a temporary directory it
# removes on exit.

set -euo pipefail
export LC_ALL=C

PROG=verify-release.sh
NAMES="NOTICES.md krutho_verifier.h libkrutho_verifier-linux-aarch64.so libkrutho_verifier-linux-x86_64.so"
STEP=start

usage() {
  sed -n '3,/^set -euo/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'
}

die_usage() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  printf 'Run %s -h for usage.\n' "$PROG" >&2
  exit 2
}

fail() {
  printf '%s: FAIL (%s): %s\n' "$PROG" "$STEP" "$1" >&2
  printf '%s: STOP. Use nothing from this release.\n' "$PROG" >&2
  exit 1
}

ok() {
  printf 'ok: %s\n' "$1"
}

# Run a command, capture stdout and stderr in OUT, return its status.
OUT=
capture() {
  local rc=0
  OUT=$("$@" 2>&1) || rc=$?
  return "$rc"
}

# Success only if FILE has at least one line that does not match the extended
# regex. Exit status 2 (a grep error) is a failure, never a pass.
has_line_outside() {
  local rc=0
  grep -a -q -v -E "$1" "$2" || rc=$?
  case $rc in
    0) return 0 ;;
    1) return 1 ;;
    *) fail "grep could not read $2" ;;
  esac
}

# Count the lines of FILE that start with PREFIX.
count_prefix() {
  awk -v k="$1" 'index($0, k) == 1 { c++ } END { print c + 0 }' "$2"
}

# Print the text after PREFIX on the (single) line of FILE that starts with it.
value_of() {
  awk -v k="$1" 'index($0, k) == 1 { print substr($0, length(k) + 1) }' "$2"
}

# Number of lines in FILE that have at least one field.
nonblank_lines() {
  awk 'NF { n++ } END { print n + 0 }' "$1"
}

sha256_of() {
  local out
  if [ "$SHA_TOOL" = sha256sum ]; then
    out=$(sha256sum < "$1") || return 1
  else
    out=$(shasum -a 256 < "$1") || return 1
  fi
  out=${out%% *}
  case $out in
    *[!0-9a-f]* | '') return 1 ;;
  esac
  [ "${#out}" -eq 64 ] || return 1
  printf '%s\n' "$out"
}

# Validate YYYY-MM-DDTHH:MM:SSZ as a real UTC date and time. Print it as
# YYYYMMDDHHMMSS so that two values compare as strings. Return 1 if it is
# malformed or not a real date. No date(1) parsing, so GNU and BSD agree.
ts_norm() {
  local re='^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z$'
  local y mo d h mi s dim
  [[ $1 =~ $re ]] || return 1
  y=$((10#${BASH_REMATCH[1]}))
  mo=$((10#${BASH_REMATCH[2]}))
  d=$((10#${BASH_REMATCH[3]}))
  h=$((10#${BASH_REMATCH[4]}))
  mi=$((10#${BASH_REMATCH[5]}))
  s=$((10#${BASH_REMATCH[6]}))
  [ "$mo" -ge 1 ] && [ "$mo" -le 12 ] || return 1
  case $mo in
    1 | 3 | 5 | 7 | 8 | 10 | 12) dim=31 ;;
    4 | 6 | 9 | 11) dim=30 ;;
    *)
      if [ $((y % 400)) -eq 0 ] || { [ $((y % 4)) -eq 0 ] && [ $((y % 100)) -ne 0 ]; }; then
        dim=29
      else
        dim=28
      fi
      ;;
  esac
  [ "$d" -ge 1 ] && [ "$d" -le "$dim" ] || return 1
  [ "$h" -le 23 ] && [ "$mi" -le 59 ] && [ "$s" -le 59 ] || return 1
  printf '%s%s%s%s%s%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" \
    "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}" "${BASH_REMATCH[6]}"
}

# ---- Options -------------------------------------------------------------

REL=
K=
ALLOWED=
PINS=

while getopts 'r:k:a:p:h' opt; do
  case $opt in
    r) REL=$OPTARG ;;
    k) K=$OPTARG ;;
    a) ALLOWED=$OPTARG ;;
    p) PINS="$PINS$OPTARG"$'\n' ;;
    h) usage; exit 0 ;;
    *) die_usage "bad option" ;;
  esac
done
shift $((OPTIND - 1))
[ "$#" -eq 0 ] || die_usage "unexpected argument: $1"
[ -n "$REL" ] || die_usage "missing -r RELEASE_DIR"
[ -n "$K" ] || die_usage "missing -k KEYS_DIR"
[ -n "$ALLOWED" ] || die_usage "missing -a ALLOWED_SIGNERS"

# Check each pin's form before any verification starts.
SEEN=" "
while IFS= read -r pin; do
  [ -n "$pin" ] || continue
  pname=${pin%%=*}
  phash=${pin#*=}
  [ "$pname" != "$pin" ] || die_usage "pin '$pin' is not NAME=SHA256"
  case " $NAMES " in
    *" $pname "*) ;;
    *) die_usage "pin names an unknown file: $pname" ;;
  esac
  case $SEEN in
    *" $pname "*) die_usage "two pins for $pname" ;;
  esac
  SEEN="$SEEN$pname "
  case $phash in
    *[!0-9a-f]* | '') die_usage "pin for $pname is not 64 lowercase hex characters" ;;
  esac
  [ "${#phash}" -eq 64 ] || die_usage "pin for $pname is not 64 lowercase hex characters"
done <<EOF
$PINS
EOF

# ---- Tools ---------------------------------------------------------------

for tool in ssh-keygen awk grep sort diff cut date mktemp sed; do
  command -v "$tool" > /dev/null 2>&1 || die_usage "required tool not found: $tool"
done
if command -v sha256sum > /dev/null 2>&1; then
  SHA_TOOL=sha256sum
elif command -v shasum > /dev/null 2>&1; then
  SHA_TOOL=shasum
else
  die_usage "required tool not found: sha256sum or shasum"
fi

W=$(mktemp -d) || die_usage "cannot create a temporary directory"
trap 'rm -rf "$W"' EXIT

# ---- Step 2: the pinned key and the root key -----------------------------

STEP="step 2, pinned key"
[ -f "$ALLOWED" ] && [ -r "$ALLOWED" ] || fail "cannot read the allowed_signers file: $ALLOWED"
[ "$(nonblank_lines "$ALLOWED")" -eq 1 ] \
  || fail "the allowed_signers file must hold exactly one line, the pinned line"
[ "$(awk 'NF { print NF }' "$ALLOWED")" -eq 4 ] \
  || fail "the pinned line must have exactly four fields"
[ "$(awk 'NF { print $1 }' "$ALLOWED")" = "krutho-release" ] \
  || fail "the pinned line must start with the principal krutho-release"
[ "$(awk 'NF { print $2 }' "$ALLOWED")" = 'cert-authority,namespaces="krutho-release"' ] \
  || fail 'the pinned line options must be cert-authority,namespaces="krutho-release"'
PIN_KEY=$(awk 'NF { print $3 " " $4 }' "$ALLOWED")
printf '%s\n' "$PIN_KEY" > "$W/pin.pub"
capture ssh-keygen -l -E sha256 -f "$W/pin.pub" || fail "the pinned key is not a valid public key: $OUT"
ok "pinned key $OUT"
printf '    Confirm this fingerprint with Krutho out of band.\n'

STEP="step 2, root key"
ROOT="$K/release-root.pub"
[ -f "$ROOT" ] && [ -r "$ROOT" ] || fail "cannot read $ROOT"
[ "$(nonblank_lines "$ROOT")" -eq 1 ] || fail "release-root.pub must hold exactly one key"
capture ssh-keygen -l -E sha256 -f "$ROOT" || fail "release-root.pub is not a valid public key: $OUT"
ROOT_KEY=$(awk 'NF { print $1 " " $2 }' "$ROOT")
[ "$ROOT_KEY" = "$PIN_KEY" ] || fail "release-root.pub differs from the pinned key"
ok "downloaded root key equals the pinned key"

# ---- Step 3: revocation statement, form, freshness, list -----------------

R="$K/revocation.txt"
SIG="$K/revocation.txt.sig"
KRL="$K/revoked.krl"

STEP="step 3, revocation signature"
for f in "$R" "$SIG" "$KRL"; do
  [ -f "$f" ] && [ -r "$f" ] || fail "cannot read $f"
done
printf 'krutho-root namespaces="krutho-revocation" %s\n' "$PIN_KEY" > "$W/allowed_root"
capture ssh-keygen -Y verify -f "$W/allowed_root" -I krutho-root -n krutho-revocation -s "$SIG" < "$R" \
  || fail "the revocation statement signature does not verify against the pinned key: $OUT"
ok "revocation statement signed by the pinned key"

STEP="step 3, revocation form"
TS='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'
if has_line_outside "^(sequence: [1-9][0-9]*|issued: $TS|next_update: $TS|krl_sha256: [0-9a-f]{64}|recovery_sha256: [0-9a-f]{64})\$" "$R"; then
  fail "revocation.txt has a line outside the allowed forms"
fi
for field in sequence issued next_update krl_sha256; do
  [ "$(count_prefix "$field: " "$R")" -eq 1 ] || fail "revocation.txt must carry $field exactly once"
done
ok "revocation statement form"

STEP="step 3, revocation freshness"
ISSUED=$(value_of 'issued: ' "$R")
NEXT=$(value_of 'next_update: ' "$R")
ISSUED_N=$(ts_norm "$ISSUED") || fail "issued is not a valid UTC timestamp: $ISSUED"
NEXT_N=$(ts_norm "$NEXT") || fail "next_update is not a valid UTC timestamp: $NEXT"
NOW_N=$(date -u +%Y%m%d%H%M%S)
case $NOW_N in
  *[!0-9]* | '') fail "date(1) did not return a UTC timestamp" ;;
esac
[ "${#NOW_N}" -eq 14 ] || fail "date(1) did not return a UTC timestamp"
[[ $ISSUED_N < $NEXT_N ]] || fail "issued ($ISSUED) is not before next_update ($NEXT)"
[[ $ISSUED_N < $NOW_N || $ISSUED_N == "$NOW_N" ]] || fail "the statement is issued in the future ($ISSUED)"
[[ $NOW_N < $NEXT_N ]] || fail "the revocation statement expired at $NEXT"
ok "revocation statement is fresh (issued $ISSUED, next update $NEXT)"

STEP="step 3, revocation list"
WANT_KRL=$(value_of 'krl_sha256: ' "$R")
GOT_KRL=$(sha256_of "$KRL") || fail "cannot hash revoked.krl"
[ "$GOT_KRL" = "$WANT_KRL" ] || fail "revoked.krl hash $GOT_KRL does not equal krl_sha256 $WANT_KRL"
capture ssh-keygen -Q -l -f "$KRL" || fail "revoked.krl does not parse as an OpenSSH KRL: $OUT"
ok "revoked.krl matches the statement and parses"

# ---- Step 4: release signature -------------------------------------------

STEP="step 4, release signature"
SUMS="$REL/SHA256SUMS"
SUMSIG="$REL/SHA256SUMS.sig"
for f in "$SUMS" "$SUMSIG"; do
  [ -f "$f" ] && [ -r "$f" ] || fail "cannot read $f"
done
capture ssh-keygen -Y verify -f "$ALLOWED" -I krutho-release -n krutho-release -s "$SUMSIG" -r "$KRL" < "$SUMS" \
  || fail "the SHA256SUMS signature does not verify: $OUT"
case $OUT in
  'Good "krutho-release" signature'*) ;;
  *) fail "unexpected signature check output: $OUT" ;;
esac
ok "SHA256SUMS signature: $OUT"

# ---- Step 5: the file list and the file hashes ---------------------------

STEP="step 5, SHA256SUMS list"
if has_line_outside '^[0-9a-f]{64}  [^ ]+$' "$SUMS"; then
  fail "SHA256SUMS has a line that is not '<64 hex characters>', two spaces, name"
fi
# shellcheck disable=SC2086
printf '%s\n' $NAMES | sort > "$W/expected"
cut -c67- "$SUMS" | sort > "$W/listed"
diff "$W/listed" "$W/expected" > "$W/names.diff" \
  || fail "SHA256SUMS must list exactly the four expected names once each"
ok "SHA256SUMS lists exactly the four expected names"

STEP="step 5, file hashes"
for name in $NAMES; do
  file="$REL/$name"
  [ -f "$file" ] && [ -r "$file" ] || fail "cannot read $file"
  want=$(awk -v n="$name" 'substr($0, 67) == n { print substr($0, 1, 64) }' "$SUMS")
  got=$(sha256_of "$file") || fail "cannot hash $file"
  [ "$got" = "$want" ] || fail "$name hash $got does not equal the signed hash $want"
  ok "$name $got"
done

# ---- Step 6: your pins ---------------------------------------------------

STEP="step 6, pins"
NPINS=0
while IFS= read -r pin; do
  [ -n "$pin" ] || continue
  pname=${pin%%=*}
  phash=${pin#*=}
  want=$(awk -v n="$pname" 'substr($0, 67) == n { print substr($0, 1, 64) }' "$SUMS")
  [ "$want" = "$phash" ] || fail "$pname: signed hash $want does not equal your pin $phash"
  ok "$pname equals your pin"
  NPINS=$((NPINS + 1))
done <<EOF
$PINS
EOF

if [ "$NPINS" -eq 0 ]; then
  printf 'NOTE: no -p pins were given, so the script did not check which version these files are.\n'
  printf '      Compare each file you use with the hash pinned in your own source (VERIFY.md, step 6).\n'
fi
printf 'PASS: the release in %s verified.\n' "$REL"
exit 0
