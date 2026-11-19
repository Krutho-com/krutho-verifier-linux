# Krutho verifier for Linux

Signed Krutho verifier library for Linux (x86_64, aarch64). It verifies Krutho credentials inside your own software. This repository carries releases only: binaries, a header, checksums and signatures. It carries no source.

**Licence:** the Krutho Verifier Binary Licence (Pilot), approved 2026-11-18. See `LICENSE`. The licence allows use and redistribution of the unmodified signed binary, alone or bundled in other software and container images, with the licence and `NOTICES.md` alongside.

## What a release carries

Each GitHub Release (tag `verifier-v<version>`, first `verifier-v0.1.0`) has these files:

- `libkrutho_verifier-linux-x86_64.so`
- `libkrutho_verifier-linux-aarch64.so`
- `krutho/verifier_sdk.h`, the C header
- `SHA256SUMS`, hashes of the files above plus `LICENSE` and `NOTICES.md`
- `SHA256SUMS.sig`, an OpenSSH signature over `SHA256SUMS`, made by a signing key that the Krutho release root key certifies
- `LICENSE` and `NOTICES.md`

The two `.so` names carry the architecture because release assets share one flat list. Install the one for your architecture as `libkrutho_verifier.so`. Do not alter its bytes.

## Requirements

- glibc 2.36 or later, which is Debian 12 (bookworm) or later.
- x86_64 or aarch64.

## ABI

The library exports only `krutho_*` symbols. Everything else is hidden. Link against the header's functions and nothing else.

## Verify before you ship

See `VERIFY.md`. Verification is offline and needs only `ssh-keygen` and a SHA-256 tool.

## Redistributing

Ship the `.so` unmodified, with `LICENSE`, `NOTICES.md`, `SHA256SUMS` and `SHA256SUMS.sig`. Your own software keeps its own licence.
