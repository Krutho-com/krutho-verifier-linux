# Verifying a Krutho verifier release

Each release publishes four files plus a signed checksum list:

- `libkrutho_verifier-linux-x86_64.so` and `libkrutho_verifier-linux-aarch64.so`
- `krutho_verifier.h` and `NOTICES.md`
- `SHA256SUMS`, the SHA-256 hashes of those four files, one per line, by bare name
- `SHA256SUMS.sig`, an OpenSSH signature over `SHA256SUMS`, made with a signing key that the Krutho release root key certifies

Tags follow `verifier-linux-v<version>`. The first release is `verifier-linux-v0.1.0`. Verification needs no network after you download the files.

## For software that downloads the library

If your software downloads the library on first start, pin the exact release in your own source: the version and the SHA-256 of each file you use. Never fetch "latest". An operator may also place the files in your data directory by hand. Run the same checks on those files before use.

## Rule

Stop on any mismatch, any expired statement, any command error and any failed signature. Use nothing from a release that fails a check.

## What you need

- OpenSSH `ssh-keygen` with `-Y verify` support for certificate authorities and `-r` revocation lists.
- `sha256sum` (Linux) or `shasum -a 256` (macOS).
- The root key fingerprint, which you confirm with Krutho out of band. A fingerprint read from this repository proves nothing about this repository. Contact Krutho to confirm it.
- The release root's `KEYS/` directory, from the current `main` of https://github.com/Krutho-com/krutho-sdk-swift. Always use the current copy: an old copy hides later revocations. It holds `release-root.pub`, `release-signing-cert-1.pub` (valid until 2027-11-06), `revocation.txt`, `revocation.txt.sig` and `revoked.krl`.

## The allowed_signers line

Pin this line in a file named `allowed_signers`:

```
krutho-release cert-authority,namespaces="krutho-release" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILHsuJEnJcKR5U+gR9DAUyBS4im4dy0+doygks8pjQOy
```

Confirm that this key is the one in `KEYS/release-root.pub` and that its fingerprint matches the one you confirmed with Krutho.

## 1. Download

```sh
TAG=verifier-linux-v0.1.0
mkdir assets && gh release download "$TAG" -R Krutho-com/krutho-verifier-linux -D assets
git clone https://github.com/Krutho-com/krutho-sdk-swift.git keys-src
K=keys-src/KEYS
W=$(mktemp -d)
```

Without the GitHub CLI, download the same files from the release page.

## 2. Check the root key

`release-root.pub` must hold exactly one key, and it must be the key in your `allowed_signers` line.

```sh
grep -c . "$K/release-root.pub"          # prints 1
ssh-keygen -l -E sha256 -f "$K/release-root.pub"
```

## 3. Check the revocation list

The root key signs the revocation statement. Its `krl_sha256` line must equal the hash of `revoked.krl`, and its `next_update` must be in the future.

```sh
printf 'krutho-root namespaces="krutho-revocation" %s\n' "$(cut -d' ' -f1,2 "$K/release-root.pub")" > "$W/allowed_root"
ssh-keygen -Y verify -f "$W/allowed_root" -I krutho-root -n krutho-revocation \
  -s "$K/revocation.txt.sig" < "$K/revocation.txt"
printf '%s  revoked.krl\n' "$(grep '^krl_sha256:' "$K/revocation.txt" | cut -d' ' -f2)" > "$W/krl.sum"
(cd "$K" && sha256sum -c "$W/krl.sum")     # macOS: shasum -a 256 -c
grep '^next_update:' "$K/revocation.txt"
date -u +%Y-%m-%dT%H:%M:%SZ                 # must be before next_update
```

## 4. Check the release signature

```sh
cp allowed_signers "$W/allowed_signers"
ssh-keygen -Y verify -f "$W/allowed_signers" -I krutho-release -n krutho-release \
  -s assets/SHA256SUMS.sig -r "$K/revoked.krl" < assets/SHA256SUMS
```

It must print `Good "krutho-release" signature`. If the signing certificate has expired since the release, add `-O verify-time=YYYYMMDD` with a date inside the certificate's validity, normally the release date. The revocation list applies at every verify time.

## 5. Check the files

```sh
(cd assets && sha256sum -c SHA256SUMS)      # macOS: shasum -a 256 -c SHA256SUMS
```

Every file must print `OK`. A file that does not appear in `SHA256SUMS` is unsigned: do not ship it.

## Check one installed file

Compute the SHA-256 of the installed file and compare it with its line in the verified `SHA256SUMS`. Look the line up by the original asset name, for example `libkrutho_verifier-linux-x86_64.so`, even if you installed the file under another name.

```sh
sha256sum /path/to/installed.so
grep 'libkrutho_verifier-linux-x86_64.so' assets/SHA256SUMS
```

The two hashes must be equal.

Delete the scratch directory (`rm -rf "$W"`) when you finish.
