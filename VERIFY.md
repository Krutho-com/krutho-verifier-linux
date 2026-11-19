# Verifying a Krutho verifier release

Each release publishes four files plus a signed checksum list:

- `libkrutho_verifier-linux-x86_64.so` and `libkrutho_verifier-linux-aarch64.so`
- `krutho_verifier.h` and `NOTICES.md`
- `SHA256SUMS`, the SHA-256 hashes of those four files, one per line, by bare name
- `SHA256SUMS.sig`, an OpenSSH signature over `SHA256SUMS`, made with a signing key that the Krutho release root key certifies

Tags follow `verifier-linux-v<version>`. The first release is `verifier-linux-v0.1.0`. Verification needs no network after you download the files.

## Rule

`verify-release.sh` is the only supported way to verify a release. Use nothing from a release unless the script exits 0 and its last line starts with `PASS:`. Stop on any other result: a failed check, a changed file, an expired statement, a bad signature, a missing pin or an error.

## What you need

- A recent OpenSSH, one whose `ssh-keygen` supports `-Y verify` with `-r`. Tested with OpenSSH 10.3 and with the OpenSSH 9.2 that Debian 12 ships.
- These tools: `ssh-keygen`, `sha256sum` or `shasum -a 256`, `date`, `awk`, `grep`, `cut`, `sort`, `diff`, `sed`, `mktemp`, `cat`, and `bash` (3.2 or later) to run `verify-release.sh`. Linux and macOS have them. To download the files you need `git` and `gh`, or a browser.
- The root key fingerprint, which you confirm with Krutho out of band. A fingerprint read from this repository proves nothing about this repository.
- The release root's `KEYS/` directory, from the current `main` of https://github.com/Krutho-com/krutho-sdk-swift. Always use the current copy: an old copy hides later revocations. It holds `release-root.pub`, `release-signing-cert-1.pub`, `revocation.txt`, `revocation.txt.sig` and `revoked.krl`.
- The SHA-256 of each release file you use, from your own pinned source (see step 6).

## The allowed_signers line

Pin this line in a file named `allowed_signers`:

```
krutho-release cert-authority,namespaces="krutho-release" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILHsuJEnJcKR5U+gR9DAUyBS4im4dy0+doygks8pjQOy
```

The file must contain exactly this one line and nothing else: no second line, no blank or whitespace-only line and no comment. Confirm that its fingerprint matches the one you confirmed with Krutho. Everything below trusts this pinned key, not the copy you download.

## Step 1. Download

```sh
TAG=verifier-linux-v0.1.0
mkdir assets && gh release download "$TAG" -R Krutho-com/krutho-verifier-linux -D assets
git clone --depth 1 https://github.com/Krutho-com/krutho-sdk-swift.git keys-src
```

Without the GitHub CLI, download the same files from the release page. The script does not download anything.

## Run the script

`verify-release.sh`, in the root of this repository, performs steps 2 to 6 below and stops at the first failure. Read the script before you rely on it. Keep your reviewed copy with your pins.

```sh
./verify-release.sh -r assets -k keys-src/KEYS -a allowed_signers \
  -p NOTICES.md=<sha256 from your source> \
  -p krutho_verifier.h=<sha256 from your source> \
  -p libkrutho_verifier-linux-aarch64.so=<sha256 from your source> \
  -p libkrutho_verifier-linux-x86_64.so=<sha256 from your source>
echo "exit status $?"
```

- `-r` is the directory with the four files, `SHA256SUMS` and `SHA256SUMS.sig`.
- `-k` is the `KEYS` directory from the current `main` of `krutho-sdk-swift`.
- `-a` is your pinned `allowed_signers` file.
- `-p NAME=SHA256` is the hash from your own source for one file. Repeat it for each file you use. At least one `-p` is required, because the signed list names no version.
- `--signature-only` runs steps 2 to 5 without a pin. See below.
- `-h` prints the usage.

Exit status:

| Status | Meaning |
|---|---|
| 0 | Every check passed and every pin matched. The last line is `PASS: ...`. With `--signature-only`, steps 2 to 5 passed and the output says `SIGNATURE ONLY: version not pinned`. |
| 1 | A check failed, or an unexpected error occurred. The message on stderr names the step. |
| 2 | Bad usage, or a required tool is missing. |
| 3 | Steps 2 to 5 passed, but you gave no `-p` pin: `not verified: no version pin`. |

With status 0 and at least one `-p` pin, every check passed and each pinned file equals its pin. The `PASS:` line says how many of the four files you pinned. A `note:` line above it lists any file without a pin. Use only the files you pinned.

`--signature-only` is for a check that cannot know the version, for example a first look at a release before you pin it. A `SIGNATURE ONLY` result shows that Krutho signed these files. It does not show which version they are, so it never replaces step 6. Do not release or install on it. It cannot be combined with `-p`.

## For software that downloads the library

Pin the exact release in your own source: the version and the SHA-256 of each file you use. Never fetch "latest". An operator may also place the files in your data directory by hand. Run `verify-release.sh` on those files before use. Step 6 is part of the verification, not an extra.

## Certificate expiry

Signing certificate 1 (`KEYS/release-signing-cert-1.pub`) is valid to 2027-11-06. An expired signing certificate fails step 4.

Before a signing certificate expires, Krutho re-signs every supported release with the renewed certificate and publishes the renewed certificate in `KEYS`. The re-signing produces only a new `SHA256SUMS.sig`. The four files and `SHA256SUMS` stay byte for byte the same, so the hashes you pinned stay valid. Download the release again to get the new `SHA256SUMS.sig`, and use the current `KEYS`.

## What the script checks

These are the checks behind steps 2 to 6. This section explains them so you can read the script and judge its output. It is not a procedure to run by hand. The script copies the keys, the revocation inputs, `allowed_signers`, `SHA256SUMS` and its signature to a private temporary directory before it checks them, and it turns any unexpected error into a failed check. It hashes the four release files where they sit, so keep the release directory private to the user running the check (not writable by anyone else), and install the files from that same directory after the script exits 0. Commands typed by hand do neither.

### 2. The root key against the pin

`release-root.pub` must hold exactly one key, and it must equal the key in your pinned `allowed_signers` line. Everything that follows trusts the pinned key, so a root key that differs from the pin fails. The script also checks that the pinned line has the principal `krutho-release`, the options `cert-authority,namespaces="krutho-release"` and a valid public key, and it prints the pinned key's fingerprint for you to confirm with Krutho.

### 3. The revocation statement and list

The root key signs the revocation statement in the namespace `krutho-revocation`. The script builds the verification file from the pinned key, never from the downloaded `release-root.pub`. It then checks the form of `revocation.txt`: exactly these lines, in any order, and nothing else. The first four appear once each.

```
sequence: <integer, 1 or more>
issued: <YYYY-MM-DDTHH:MM:SSZ>
next_update: <YYYY-MM-DDTHH:MM:SSZ, after issued>
krl_sha256: <64 lowercase hex characters>
recovery_sha256: <64 lowercase hex characters>    (zero or more lines)
```

The statement is fresh only if `issued` is at or before now, now is before `next_update`, and `issued` is before `next_update`. Both timestamps must be real UTC dates and times: month 01 to 12, a day that exists in that month, hour 00 to 23, minute and second 00 to 59. A malformed or impossible timestamp fails. The script validates the date itself and does not parse it with `date`, so GNU and BSD systems behave alike. An expired statement fails: fetch the current `main` again, or ask Krutho for the current statement.

The SHA-256 of `revoked.krl` must equal `krl_sha256`, and the file must parse as an OpenSSH key revocation list (KRL).

### 4. The release signature

The script verifies `SHA256SUMS.sig` over `SHA256SUMS` against your pinned line, in the namespace `krutho-release`, and always passes the revocation list. A certificate that is expired, revoked, from another authority or without the `krutho-release` principal fails. There is no workaround for a failure, including an expired signing certificate. If the certificate expired, download the release again after Krutho re-signs it (see Certificate expiry). To read a certificate's validity, run `ssh-keygen -L -f keys-src/KEYS/release-signing-cert-1.pub`.

### 5. The files

`SHA256SUMS` must list exactly the four expected names, once each, in the form `<64 hex characters>`, two spaces, name. The script then hashes each of the four files and requires each hash to equal its line. A file that does not appear in `SHA256SUMS` is unsigned: do not ship it. The script prints the SHA-256 of each file it verified.

### 6. Your pins

`SHA256SUMS` names no version. The signature proves only that Krutho signed these hashes, not that they belong to the version your software expects. For every file you use, the script compares the signed hash with the SHA-256 you pass with `-p`, which you take from the version pinned in your own source. It refuses any mismatch, so a signed list from another release does not pass. Pin all four files: `NOTICES.md`, `krutho_verifier.h`, `libkrutho_verifier-linux-aarch64.so` and `libkrutho_verifier-linux-x86_64.so`. A file without a pin is checked against the signed list only.

### An installed file

The script checks the files in the release directory. An installed copy must have the same bytes. Compute the SHA-256 of the installed file and compare it with the hash the script printed for the original asset name, for example `libkrutho_verifier-linux-x86_64.so`, even if you installed the file under another name. It must also equal the hash pinned in your source.

## When verification fails

A consumer should treat a failed or missing verification as a reason to stop new approvals and enrollments, without interrupting devices it already approved.

## What this does not cover

- **Version.** `SHA256SUMS` names no version. Only your pin in step 6 prevents a downgrade to an older, validly signed release.
- **Revocation floor.** The checks confirm that the revocation statement is signed and unexpired. They do not store the highest statement sequence you have accepted, so they cannot refuse an older, unexpired statement. Fetch `KEYS` from the current `main` each time.
- **Withdrawal.** A withdrawn release still verifies. Krutho announces every withdrawal out of band.
- **Revoked signer.** If Krutho revokes a signing key, step 4 fails for every release that key signed. Krutho then publishes a replacement release and notifies customers out of band.
- **Build and tests.** A good signature shows that Krutho's release process produced these bytes. It does not independently prove the build or the tests.
