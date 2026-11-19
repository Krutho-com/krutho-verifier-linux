# Krutho verifier for Linux

The Krutho verifier library for Linux. It verifies Krutho credentials inside your own software. Krutho publishes the binaries here for the Seinn pilot and others. This repository carries releases only: binaries, a header, checksums and signatures. It carries no source.

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

See `VERIFY.md`. Verification is offline and needs only `ssh-keygen` and a SHA-256 tool.
