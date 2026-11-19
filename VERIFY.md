# Verifying a Krutho verifier release

Each release of this repository publishes these files on its GitHub Release:

- `libkrutho_verifier-linux-x86_64.so` and `libkrutho_verifier-linux-aarch64.so`;
- `krutho/verifier_sdk.h`, `LICENSE` and `NOTICES.md`;
- `SHA256SUMS`, a list of SHA-256 hashes;
- `SHA256SUMS.sig`, an OpenSSH signature over `SHA256SUMS`, made with a signing key that the Krutho release root key certifies.

Tags follow `verifier-v<version>`. The first release is `verifier-v0.1.0`.

`SHA256SUMS` binds the signature to one tag and one file set. Its first line names the tag; every other line lists one file:

```
# tag: verifier-v<version>
<64 lowercase hex characters>  <file name>
```

Exactly two spaces separate hash and name. Verification needs no network after you download the files.

## What you need

- OpenSSH `ssh-keygen` (a version that supports `-Y verify` with certificate authorities and `-r` revocation), `bash`, and `sha256sum` (Linux) or `shasum -a 256` (macOS).
- The root key fingerprint, which Krutho sends you out of band. Krutho's current release root is `SHA256:MrXoXDdJ3pWzOpeHQX59AI5/xR/NteLYnEUNYyFqcqg`; confirm it with Krutho directly. A fingerprint read from this repository proves nothing about this repository.
- The current `KEYS/` directory (`release-root.pub`, `revocation.txt`, `revocation.txt.sig`, `revoked.krl`). The same release root signs the Swift SDK, so take `KEYS/` from the current `main` of `https://github.com/Krutho-com/krutho-sdk-swift`. Always use the current copy: an old copy hides later revocations.

## 1. Download

```sh
TAG=verifier-v0.1.0
mkdir assets && gh release download "$TAG" -R Krutho-com/krutho-verifier-linux -D assets
git clone https://github.com/Krutho-com/krutho-sdk-swift.git keys-src   # for KEYS/
```

Without the GitHub CLI, download the same files from the release page.

## 2. Check the root key

`KEYS/release-root.pub` must hold exactly one key, and its fingerprint must equal the one Krutho sent you.

```sh
K=keys-src/KEYS
grep -c . "$K/release-root.pub"                  # prints 1
ssh-keygen -l -E sha256 -f "$K/release-root.pub"
```

## 3. Check the revocation list

The statement is signed by the root key. Its `krl_sha256` line must equal the hash of `revoked.krl`, and its `next_update` must lie in the future (`date -u +%Y-%m-%dT%H:%M:%SZ`).

```sh
W=$(mktemp -d)
printf 'krutho-root namespaces="krutho-revocation" %s\n' "$(cut -d' ' -f1,2 "$K/release-root.pub")" > "$W/allowed_root"
ssh-keygen -Y verify -f "$W/allowed_root" -I krutho-root -n krutho-revocation \
  -s "$K/revocation.txt.sig" < "$K/revocation.txt"
sha256sum "$K/revoked.krl"; grep '^krl_sha256:' "$K/revocation.txt"
grep '^next_update:' "$K/revocation.txt"
```

## 4. Check the release signature

```sh
printf 'krutho-release cert-authority,namespaces="krutho-release" %s\n' "$(cut -d' ' -f1,2 "$K/release-root.pub")" > "$W/allowed_signers"
ssh-keygen -Y verify -f "$W/allowed_signers" -I krutho-release -n krutho-release \
  -s assets/SHA256SUMS.sig -r "$K/revoked.krl" < assets/SHA256SUMS
```

It must print `Good "krutho-release" signature`. For a release whose signing certificate has since expired, add `-O verify-time=YYYYMMDD` with a date inside the certificate's validity, normally the release date. The revocation list applies at every verify time.

## 5. Check the tag and the files

```sh
head -n 1 assets/SHA256SUMS            # must print: # tag: verifier-v0.1.0
tail -n +2 assets/SHA256SUMS > "$W/sums"
(cd assets && sha256sum -c "$W/sums")   # every listed file must print OK
```

`sha256sum -c` checks only listed files. A file you plan to ship that does not appear in the list is unsigned: do not ship it. On macOS, use `shasum -a 256 -c`.

Delete the scratch directory (`rm -rf "$W"`) when you finish. A release that passes steps 2 to 5 is the one Krutho signed.
