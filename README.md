# Krutho verifier for Linux

The Krutho verifier library for Linux. It verifies Krutho credentials inside your own software. Krutho publishes the binaries here for pilot customers. This repository carries releases only: binaries, a header, checksums and signatures. It carries no source.

## What a release carries

Each GitHub Release (tag `verifier-linux-v<version>`, first `verifier-linux-v0.1.0`) has these files:

- `libkrutho_verifier-linux-x86_64.so`
- `libkrutho_verifier-linux-aarch64.so`
- `krutho_verifier.h`, the C header
- `NOTICES.md`, the third-party notices with the full license texts
- `SHA256SUMS`, the SHA-256 hashes of the four files above, by bare name
- `SHA256SUMS.sig`, an OpenSSH signature over `SHA256SUMS`, made by a signing key that the Krutho release root key certifies

The two `.so` names carry the architecture because release assets share one flat list. Install the one for your architecture under the name your software loads, and do not alter its bytes.

## Supported platforms

- Linux on x86_64 or aarch64.
- glibc 2.36 or later, which is Debian 12 (bookworm) or later.

The first release has no macOS build.

## ABI

The library exports only `krutho_*` symbols. Everything else is hidden. Link against the functions in `krutho_verifier.h` and nothing else.

## Verify before you ship

Run `verify-release.sh` on the downloaded files. It performs every step in `VERIFY.md`, stops at the first failure and exits 0 only if every check passed:

```sh
./verify-release.sh -r assets -k keys-src/KEYS -a allowed_signers -p <file>=<sha256> ...
```

`VERIFY.md` has the exact command, the pinned `allowed_signers` line and an explanation of each step. Verification is offline once you have the files. It needs `ssh-keygen` (OpenSSH, tested with 10.3 and 9.2), `sha256sum` or `shasum -a 256`, `date`, `awk`, `grep`, `cut`, `sort`, `diff`, `sed`, `mktemp` and `bash` 3.2 or later. To download the files you need `git` and `gh`, or a browser.
