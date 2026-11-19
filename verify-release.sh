#!/usr/bin/env bash
#
# verify-release.sh: verify a downloaded Krutho verifier release.
#
# This script performs steps 2 to 6 of VERIFY.md (step 1 is the download) and
# stops at the first failure. It is the only supported way to verify a release.
# Read VERIFY.md for what each check means and what the checks do not cover.
#
# Usage:
#   verify-release.sh -r RELEASE_DIR -k KEYS_DIR -a ALLOWED_SIGNERS -p NAME=SHA256 [-p NAME=SHA256]...
#   verify-release.sh -r RELEASE_DIR -k KEYS_DIR -a ALLOWED_SIGNERS --signature-only
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
#                       the one line pinned in VERIFY.md: no second line, no
#                       blank line, no comment.
#   -p NAME=SHA256      The SHA-256 of one release file, taken from your own
#                       pinned source (step 6 of VERIFY.md). NAME is one of the
#                       four file names. SHA256 is 64 lowercase hex characters.
#                       Repeat -p for each file you use. At least one -p is
#                       required, because the signed list names no version.
#   --signature-only    Run steps 2 to 5 without a pin and exit 0 if they pass.
#                       The output says "SIGNATURE ONLY: version not pinned".
#                       It proves the files are the ones Krutho signed, not
#                       which version they are. Cannot be combined with -p.
#   -h                  Print this help.
#
# Exit status:
#   0  every check passed and every pin matched (last line "PASS: ..."), or,
#      with --signature-only, steps 2 to 5 passed (output says "SIGNATURE ONLY")
#   1  a check failed, or an unexpected error occurred (the message on stderr
#      names the step)
#   2  bad usage, or a required tool is missing
#   3  steps 2 to 5 passed, but no -p pin was given and --signature-only was
#      not: "not verified: no version pin"
#
# Tools: ssh-keygen (OpenSSH with `-Y verify -r`), sha256sum or shasum -a 256,
# date, awk, grep, sort, diff, cut, sed, mktemp, cat. Works with bash 3.2 or
# later. The script only reads its inputs. It writes to a temporary directory
# it removes on exit.

set -euo pipefail
export LC_ALL=C

PROG=verify-release.sh
NAMES="NOTICES.md krutho_verifier.h libkrutho_verifier-linux-aarch64.so libkrutho_verifier-linux-x86_64.so"
STEP=setup
DONE=
W=

usage() {
  sed -n '3,/^set -euo/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'
}

# Every deliberate exit sets DONE first. The EXIT trap treats any other exit
# (a command that failed under set -e, an unset variable, a signal) as a failed
# check: it names the step and exits 1, never 2 or 3.
# shellcheck disable=SC2329
cleanup() {
  local rc=$?
  [ -z "$W" ] || rm -rf "$W"
  if [ -z "$DONE" ]; then
    printf '%s: FAIL (%s): unexpected error (status %s)\n' "$PROG" "$STEP" "$rc" >&2
    printf '%s: STOP. Use nothing from this release.\n' "$PROG" >&2
    trap - EXIT
    exit 1
  fi
}
trap cleanup EXIT

die_usage() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  printf 'Run %s -h for usage.\n' "$PROG" >&2
  DONE=1
  exit 2
}

fail() {
  printf '%s: FAIL (%s): %s\n' "$PROG" "$STEP" "$1" >&2
  printf '%s: STOP. Use nothing from this release.\n' "$PROG" >&2
  DONE=1
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

# Succeed if $1 is a non-negative integer equal to $2. Anything that is not an
# integer is an internal error and a failure, never a pass.
num_eq() {
  case $1 in
    '' | *[!0-9]*) fail "internal error: expected a number, got '$1'" ;;
  esac
  [ "$1" -eq "$2" ]
}

# Copy $1 to $2. Every later read uses the copy, so a file that changes after
# this point cannot change what was verified.
snap() {
  [ -f "$1" ] && [ -r "$1" ] || fail "cannot read $1"
  cat < "$1" > "$2" || fail "cannot copy $1"
}

# Success only if FILE has at least one line that does not match the extended
# regex. Exit status 2 (a grep error) is a failure, never a pass. FILE is
# always one of our own copies, read through a redirect.
has_line_outside() {
  local rc=0
  [ -f "$2" ] && [ -r "$2" ] || fail "cannot read $2"
  grep -a -q -v -E "$1" < "$2" || rc=$?
  case $rc in
    0) return 0 ;;
    1) return 1 ;;
    *) fail "grep could not read $2" ;;
  esac
}

# The awk helpers read FILE from standard input, never as an operand: an
# operand of the form name=value is an assignment to awk, not a file.

# Count the lines of FILE that start with PREFIX.
count_prefix() {
  awk -v k="$1" 'index($0, k) == 1 { c++ } END { print c + 0 }' < "$2"
}

# Print the text after PREFIX on the line of FILE that starts with it.
value_of() {
  awk -v k="$1" 'index($0, k) == 1 { print substr($0, length(k) + 1) }' < "$2"
}

# Line counts for FILE: all lines, lines with no field (empty or only blanks),
# lines with a carriage return, and lines with at least one field.
line_count() {
  awk 'END { print NR + 0 }' < "$1"
}
blank_lines() {
  awk 'NF == 0 { n++ } END { print n + 0 }' < "$1"
}
cr_lines() {
  awk 'index($0, "\r") { n++ } END { print n + 0 }' < "$1"
}
nonblank_lines() {
  awk 'NF { n++ } END { print n + 0 }' < "$1"
}

# The signed hash of file NAME, from the copy of SHA256SUMS.
hash_for() {
  awk -v n="$1" 'substr($0, 67) == n { print substr($0, 1, 64) }' < "$W/SHA256SUMS"
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
SIGONLY=0

# getopts has no long options. Take out --signature-only first, and leave any
# argument that is the value of -r, -k, -a or -p alone.
ARGS=()
expect=0
for arg in "$@"; do
  if [ "$expect" -eq 1 ]; then
    ARGS+=("$arg")
    expect=0
    continue
  fi
  case $arg in
    --signature-only) SIGONLY=1 ;;
    -[rkap]) ARGS+=("$arg"); expect=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}

while getopts 'r:k:a:p:h' opt; do
  case $opt in
    r) REL=$OPTARG ;;
    k) K=$OPTARG ;;
    a) ALLOWED=$OPTARG ;;
    p) PINS="$PINS$OPTARG"$'\n' ;;
    h) usage; DONE=1; exit 0 ;;
    *) die_usage "bad option" ;;
  esac
done
shift $((OPTIND - 1))
[ "$#" -eq 0 ] || die_usage "unexpected argument: $1"
[ -n "$REL" ] || die_usage "missing -r RELEASE_DIR"
[ -n "$K" ] || die_usage "missing -k KEYS_DIR"
[ -n "$ALLOWED" ] || die_usage "missing -a ALLOWED_SIGNERS"
[ "$SIGONLY" -eq 0 ] || [ -z "$PINS" ] || die_usage "--signature-only cannot be combined with -p"

# Check each pin's form before any verification starts.
SEEN=" "
NPINS=0
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
  NPINS=$((NPINS + 1))
done <<EOF
$PINS
EOF

# ---- Tools ---------------------------------------------------------------

for tool in ssh-keygen awk grep sort diff cut date mktemp sed cat; do
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

# ---- Step 2: the pinned key and the root key -----------------------------

STEP="step 2, pinned key"
snap "$ALLOWED" "$W/allowed_signers"
A="$W/allowed_signers"
n=$(blank_lines "$A") || fail "cannot read the allowed_signers file: $ALLOWED"
num_eq "$n" 0 || fail "the allowed_signers file must hold exactly one line, the pinned line, with no blank or whitespace-only line"
n=$(line_count "$A") || fail "cannot read the allowed_signers file: $ALLOWED"
num_eq "$n" 1 || fail "the allowed_signers file must hold exactly one line, the pinned line"
n=$(cr_lines "$A") || fail "cannot read the allowed_signers file: $ALLOWED"
num_eq "$n" 0 || fail "the allowed_signers file must not contain carriage returns"
n=$(awk '{ print NF }' < "$A") || fail "cannot read the allowed_signers file: $ALLOWED"
num_eq "$n" 4 || fail "the pinned line must have exactly four fields"
n=$(awk '{ print $1 }' < "$A") || fail "cannot read the allowed_signers file: $ALLOWED"
[ "$n" = "krutho-release" ] || fail "the pinned line must start with the principal krutho-release"
n=$(awk '{ print $2 }' < "$A") || fail "cannot read the allowed_signers file: $ALLOWED"
[ "$n" = 'cert-authority,namespaces="krutho-release"' ] \
  || fail 'the pinned line options must be cert-authority,namespaces="krutho-release"'
PIN_KEY=$(awk '{ print $3 " " $4 }' < "$A") || fail "cannot read the allowed_signers file: $ALLOWED"
printf '%s\n' "$PIN_KEY" > "$W/pin.pub"
capture ssh-keygen -l -E sha256 -f "$W/pin.pub" || fail "the pinned key is not a valid public key: $OUT"
ok "pinned key $OUT"
printf '    Confirm this fingerprint with Krutho out of band.\n'

STEP="step 2, root key"
snap "$K/release-root.pub" "$W/release-root.pub"
ROOT="$W/release-root.pub"
n=$(nonblank_lines "$ROOT") || fail "cannot read $K/release-root.pub"
num_eq "$n" 1 || fail "release-root.pub must hold exactly one key"
capture ssh-keygen -l -E sha256 -f "$ROOT" || fail "release-root.pub is not a valid public key: $OUT"
ROOT_KEY=$(awk 'NF { print $1 " " $2 }' < "$ROOT") || fail "cannot read $K/release-root.pub"
[ "$ROOT_KEY" = "$PIN_KEY" ] || fail "release-root.pub differs from the pinned key"
ok "downloaded root key equals the pinned key"

# ---- Step 3: revocation statement, form, freshness, list -----------------

STEP="step 3, revocation signature"
snap "$K/revocation.txt" "$W/revocation.txt"
snap "$K/revocation.txt.sig" "$W/revocation.txt.sig"
snap "$K/revoked.krl" "$W/revoked.krl"
R="$W/revocation.txt"
SIG="$W/revocation.txt.sig"
KRL="$W/revoked.krl"
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
  n=$(count_prefix "$field: " "$R") || fail "cannot read revocation.txt"
  num_eq "$n" 1 || fail "revocation.txt must carry $field exactly once"
done
ok "revocation statement form"

STEP="step 3, revocation freshness"
ISSUED=$(value_of 'issued: ' "$R") || fail "cannot read revocation.txt"
NEXT=$(value_of 'next_update: ' "$R") || fail "cannot read revocation.txt"
ISSUED_N=$(ts_norm "$ISSUED") || fail "issued is not a valid UTC timestamp: $ISSUED"
NEXT_N=$(ts_norm "$NEXT") || fail "next_update is not a valid UTC timestamp: $NEXT"
NOW_N=$(date -u +%Y%m%d%H%M%S) || fail "date(1) failed"
case $NOW_N in
  *[!0-9]* | '') fail "date(1) did not return a UTC timestamp" ;;
esac
[ "${#NOW_N}" -eq 14 ] || fail "date(1) did not return a UTC timestamp"
[[ $ISSUED_N < $NEXT_N ]] || fail "issued ($ISSUED) is not before next_update ($NEXT)"
[[ $ISSUED_N < $NOW_N || $ISSUED_N == "$NOW_N" ]] || fail "the statement is issued in the future ($ISSUED)"
[[ $NOW_N < $NEXT_N ]] || fail "the revocation statement expired at $NEXT"
ok "revocation statement is fresh (issued $ISSUED, next update $NEXT)"

STEP="step 3, revocation list"
WANT_KRL=$(value_of 'krl_sha256: ' "$R") || fail "cannot read revocation.txt"
GOT_KRL=$(sha256_of "$KRL") || fail "cannot hash revoked.krl"
[ "$GOT_KRL" = "$WANT_KRL" ] || fail "revoked.krl hash $GOT_KRL does not equal krl_sha256 $WANT_KRL"
capture ssh-keygen -Q -l -f "$KRL" || fail "revoked.krl does not parse as an OpenSSH KRL: $OUT"
ok "revoked.krl matches the statement and parses"

# ---- Step 4: release signature -------------------------------------------

STEP="step 4, release signature"
snap "$REL/SHA256SUMS" "$W/SHA256SUMS"
snap "$REL/SHA256SUMS.sig" "$W/SHA256SUMS.sig"
SUMS="$W/SHA256SUMS"
SUMSIG="$W/SHA256SUMS.sig"
capture ssh-keygen -Y verify -f "$A" -I krutho-release -n krutho-release -s "$SUMSIG" -r "$KRL" < "$SUMS" \
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
cut -c67- < "$SUMS" | sort > "$W/listed"
diff "$W/listed" "$W/expected" > "$W/names.diff" \
  || fail "SHA256SUMS must list exactly the four expected names once each"
ok "SHA256SUMS lists exactly the four expected names"

STEP="step 5, file hashes"
for name in $NAMES; do
  file="$REL/$name"
  [ -f "$file" ] && [ -r "$file" ] || fail "cannot read $file"
  want=$(hash_for "$name") || fail "cannot read SHA256SUMS"
  got=$(sha256_of "$file") || fail "cannot hash $file"
  [ "$got" = "$want" ] || fail "$name hash $got does not equal the signed hash $want"
  ok "$name $got"
done

# ---- Step 6: your pins ---------------------------------------------------

STEP="step 6, pins"
if [ "$NPINS" -eq 0 ]; then
  if [ "$SIGONLY" -eq 1 ]; then
    printf 'SIGNATURE ONLY: version not pinned.\n'
    printf '    Steps 2 to 5 passed: Krutho signed these files. Nothing shows which version they are.\n'
    printf '    Do not release or install on this result. Pin each file with -p (VERIFY.md, step 6).\n'
    DONE=1
    exit 0
  fi
  printf '%s: not verified: no version pin\n' "$PROG" >&2
  printf '%s: steps 2 to 5 passed, but no -p pin was given, so nothing shows which version these files are.\n' "$PROG" >&2
  printf '%s: pass -p NAME=SHA256 from your own pinned source for each file you use (VERIFY.md, step 6),\n' "$PROG" >&2
  printf '%s: or pass --signature-only to run steps 2 to 5 alone.\n' "$PROG" >&2
  DONE=1
  exit 3
fi
while IFS= read -r pin; do
  [ -n "$pin" ] || continue
  pname=${pin%%=*}
  phash=${pin#*=}
  want=$(hash_for "$pname") || fail "cannot read SHA256SUMS"
  [ "$want" = "$phash" ] || fail "$pname: signed hash $want does not equal your pin $phash"
  ok "$pname equals your pin"
done <<EOF
$PINS
EOF

UNPINNED=
for name in $NAMES; do
  case $SEEN in
    *" $name "*) ;;
    *) UNPINNED="$UNPINNED $name" ;;
  esac
done
if [ -n "$UNPINNED" ]; then
  printf 'note: no pin for:%s. Use only the files you pinned.\n' "$UNPINNED"
fi
printf 'PASS: the release in %s verified, with %s of 4 files pinned.\n' "$REL" "$NPINS"
DONE=1
exit 0
