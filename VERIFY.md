# Verifying a Krutho verifier release

Each release publishes four files plus a signed checksum list:

- `libkrutho_verifier-linux-x86_64.so` and `libkrutho_verifier-linux-aarch64.so`
- `krutho_verifier.h` and `NOTICES.md`
- `SHA256SUMS`, the SHA-256 hashes of those four files, one per line, by bare name
- `SHA256SUMS.sig`, an OpenSSH signature over `SHA256SUMS`, made with a signing key that the Krutho release root key certifies

Tags follow `verifier-linux-v<version>`. The first release is `verifier-linux-v0.1.0`. Verification needs no network after you download the files.

## Rule

Stop on any mismatch, any expired statement, any command error and any failed signature. Use nothing from a release that fails a check.

## What you need

- A recent OpenSSH (one whose `ssh-keygen` supports `-Y verify` with `-r`).
- `sha256sum` (Linux) or `shasum -a 256` (macOS).
- The root key fingerprint, which you confirm with Krutho out of band. A fingerprint read from this repository proves nothing about this repository.
- The release root's `KEYS/` directory, from the current `main` of https://github.com/Krutho-com/krutho-sdk-swift. Always use the current copy: an old copy hides later revocations. It holds `release-root.pub`, `release-signing-cert-1.pub`, `revocation.txt`, `revocation.txt.sig` and `revoked.krl`.

## For software that downloads the library

Pin the exact release in your own source: the version and the SHA-256 of each file you use. Never fetch "latest". An operator may also place the files in your data directory by hand. Run the same checks on those files before use. Step 6 below is part of the verification, not an extra.

## The allowed_signers line

Pin this line in a file named `allowed_signers`:

```
krutho-release cert-authority,namespaces="krutho-release" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILHsuJEnJcKR5U+gR9DAUyBS4im4dy0+doygks8pjQOy
```

Confirm that its fingerprint matches the one you confirmed with Krutho. Everything below trusts this pinned key, not the copy you download.

## Certificate expiry

Signing certificate 1 (`KEYS/release-signing-cert-1.pub`) is valid to 2027-11-06. Krutho publishes renewals in `KEYS`. An expired signing certificate fails step 4. Use the current `KEYS` and a release signed with a current certificate.

## 1. Download

```sh
TAG=verifier-linux-v0.1.0
mkdir assets && gh release download "$TAG" -R Krutho-com/krutho-verifier-linux -D assets
git clone --depth 1 https://github.com/Krutho-com/krutho-sdk-swift.git keys-src
K=keys-src/KEYS
W=$(mktemp -d)
cp allowed_signers "$W/allowed_signers"
```

Without the GitHub CLI, download the same files from the release page.

## 2. Check the root key against the pin

`release-root.pub` must hold exactly one key, and it must equal the key in your pinned `allowed_signers` line. Stop if it does not.

```sh
grep -c . "$K/release-root.pub"          # prints 1
ssh-keygen -l -E sha256 -f "$K/release-root.pub"
if [ "$(cut -d' ' -f1,2 "$K/release-root.pub")" = "$(cut -d' ' -f3,4 allowed_signers)" ]; then
  echo "ROOT KEY MATCHES PIN"
else
  echo "ROOT KEY DIFFERS FROM PIN: STOP"
fi
```

The output must read `ROOT KEY MATCHES PIN`.

## 3. Check the revocation statement and list

The root key signs the revocation statement. Build the verification file from the pinned key, never from the downloaded `release-root.pub`.

```sh
printf 'krutho-root namespaces="krutho-revocation" %s\n' "$(cut -d' ' -f3,4 allowed_signers)" > "$W/allowed_root"
ssh-keygen -Y verify -f "$W/allowed_root" -I krutho-root -n krutho-revocation \
  -s "$K/revocation.txt.sig" < "$K/revocation.txt"
```

The form of `revocation.txt`: exactly these lines, in any order, and nothing else. The first four appear once each.

```
sequence: <integer, 1 or more>
issued: <YYYY-MM-DDTHH:MM:SSZ>
next_update: <YYYY-MM-DDTHH:MM:SSZ, after issued>
krl_sha256: <64 lowercase hex characters>
recovery_sha256: <64 lowercase hex characters>    (zero or more lines)
```

```sh
R="$K/revocation.txt"
grep -v -E '^(sequence: [1-9][0-9]*|issued: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|next_update: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|krl_sha256: [0-9a-f]{64}|recovery_sha256: [0-9a-f]{64})$' "$R"   # prints nothing
for f in sequence issued next_update krl_sha256; do grep -c "^$f: " "$R"; done                  # prints 1 four times
ISSUED=$(grep '^issued: ' "$R" | cut -d' ' -f2)
NEXT=$(grep '^next_update: ' "$R" | cut -d' ' -f2)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s\n%s\n' "$ISSUED" "$NEXT" | LC_ALL=C sort -c -u    # prints nothing: next_update is after issued
printf '%s\n%s\n' "$NOW" "$NEXT" | LC_ALL=C sort -c -u       # prints nothing: now is before next_update
```

The hash of `revoked.krl` must equal `krl_sha256`, and the file must parse as an OpenSSH KRL.

```sh
printf '%s  revoked.krl\n' "$(grep '^krl_sha256: ' "$R" | cut -d' ' -f2)" > "$W/krl.sum"
(cd "$K" && sha256sum -c "$W/krl.sum")              # Linux; prints: revoked.krl: OK
(cd "$K" && shasum -a 256 -c "$W/krl.sum")          # macOS; prints: revoked.krl: OK
ssh-keygen -Q -l -f "$K/revoked.krl"                 # must exit 0
```

An expired statement fails. Fetch the current `main` again, or ask Krutho for the current statement.

## 4. Check the release signature

Always pass the revocation list.

```sh
ssh-keygen -Y verify -f "$W/allowed_signers" -I krutho-release -n krutho-release \
  -s assets/SHA256SUMS.sig -r "$K/revoked.krl" < assets/SHA256SUMS
```

It must print `Good "krutho-release" signature`. There is no workaround for a failure, including an expired signing certificate. Read a certificate's validity with `ssh-keygen -L -f "$K/release-signing-cert-1.pub"`.

## 5. Check the files

First, `SHA256SUMS` must list exactly the four expected names, once each, in the form `<64 hex characters>`, two spaces, name.

```sh
printf '%s\n' NOTICES.md krutho_verifier.h libkrutho_verifier-linux-aarch64.so libkrutho_verifier-linux-x86_64.so \
  | LC_ALL=C sort > "$W/expected"
grep -v -E '^[0-9a-f]{64}  [^ ]+$' assets/SHA256SUMS      # prints nothing
cut -c67- assets/SHA256SUMS | LC_ALL=C sort | diff - "$W/expected" && echo NAMES OK
```

It must print `NAMES OK`. Then check each file against its line.

```sh
(cd assets && sha256sum -c SHA256SUMS)          # Linux
(cd assets && shasum -a 256 -c SHA256SUMS)      # macOS
```

Every file must print `OK`. A file that does not appear in `SHA256SUMS` is unsigned: do not ship it.

## 6. Match the files to your pin

`SHA256SUMS` names no version. The signature proves only that Krutho signed these hashes, not that they belong to the version your software expects. For every file you use, read its hash from the verified `SHA256SUMS` and compare it with the SHA-256 and the version pinned in your own source. Refuse any mismatch. A signed list from another release must not pass.

```sh
grep '  libkrutho_verifier-linux-x86_64\.so$' assets/SHA256SUMS | cut -d' ' -f1    # equals your pinned hash
grep '  libkrutho_verifier-linux-aarch64\.so$' assets/SHA256SUMS | cut -d' ' -f1  # equals your pinned hash
grep '  krutho_verifier\.h$' assets/SHA256SUMS | cut -d' ' -f1                    # equals your pinned hash
```

## Check one installed file

Compute the SHA-256 of the installed file and compare it with its line in the verified `SHA256SUMS`. Look the line up by the original asset name, for example `libkrutho_verifier-linux-x86_64.so`, even if you installed the file under another name.

```sh
sha256sum /path/to/installed.so                                   # Linux
shasum -a 256 /path/to/installed.so                               # macOS
grep '  libkrutho_verifier-linux-x86_64\.so$' assets/SHA256SUMS
```

The two hashes must be equal, and equal to the hash pinned in your source.

Delete the scratch directory (`rm -rf "$W"`) when you finish.

## When verification fails

A failed or missing verification stops approvals and new enrollments. It never stops playback or the use of devices that are already approved.

## What this does not cover

- **Version.** `SHA256SUMS` names no version. Only your pin in step 6 prevents a downgrade to an older, validly signed release.
- **Revocation floor.** The checks confirm that the revocation statement is signed and unexpired. They do not store the highest statement sequence you have accepted, so they cannot refuse an older, unexpired statement. Fetch `KEYS` from the current `main` each time.
- **Withdrawal.** A withdrawn release still verifies. Krutho announces every withdrawal out of band.
- **Revoked signer.** If Krutho revokes a signing key, step 4 fails for every release that key signed. Krutho then publishes a replacement release and notifies customers out of band.
- **Build and tests.** A good signature shows that Krutho's release process produced these bytes. It does not independently prove the build or the tests.
