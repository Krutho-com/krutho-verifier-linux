# Notices

The Krutho verifier library bundles the third-party components below. Each stays under its own licence. Versions are those compiled into the verifier at the time of the notices template (Mbed TLS 3.6.3, cJSON 1.7.18); the release build record is authoritative if it differs.

DRAFT note: the full licence texts (Apache-2.0 for Mbed TLS, the cJSON permission notice) must ship beside this file before the first release. They are not yet in this repository.

## Mbed TLS

- **Version:** 3.6.3, read from `MBEDTLS_VERSION_STRING` in `oid4vp/c/vendor/mbedtls/include/mbedtls/build_info.h`.
- **License text:** `oid4vp/c/vendor/mbedtls/LICENSE`.
- **Route:** the LICENSE opens:

  > Mbed TLS files are provided under a dual [Apache-2.0](https://spdx.org/licenses/Apache-2.0.html)
  > OR [GPL-2.0-or-later](https://spdx.org/licenses/GPL-2.0-or-later.html) license.
  > This means that users may choose which of these licenses they take the code
  > under.

  This package takes the Apache-2.0 route. Every SPDX line under `library/` and `include/` reads `SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-or-later`.
- **Copyright line:** "Copyright The Mbed TLS Contributors", as it appears in the source headers under `library/` and `include/`. The LICENSE carries no copyright line of its own.
- **What an app must retain:** Apache-2.0 section 4 ("Redistribution"), as it appears in the LICENSE, sets four conditions:
  - (a) "You must give any other recipients of the Work or Derivative Works a copy of this License"
  - (b) "You must cause any modified files to carry prominent notices stating that You changed the files"
  - (c) "You must retain, in the Source form of any Derivative Works that You distribute, all copyright, patent, trademark, and attribution notices from the Source form of the Work, excluding those notices that do not pertain to any part of the Derivative Works"
  - (d) applies "If the Work includes a "NOTICE" text file as part of its distribution". `oid4vp/c/vendor/mbedtls/` contains no NOTICE file: it holds `LICENSE`, `include/` and `library/`.

## cJSON

- **Version:** 1.7.18, read from `CJSON_VERSION_MAJOR`, `CJSON_VERSION_MINOR` and `CJSON_VERSION_PATCH` in `oid4vp/c/vendor/cjson/cJSON.h`.
- **License text:** `oid4vp/c/vendor/cjson/LICENSE`.
- **Route:** the file names no license. It is a permission notice.
- **Copyright line:** "Copyright (c) 2009-2017 Dave Gamble and cJSON contributors", the first line of the LICENSE.
- **What an app must retain:** the LICENSE states: "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software."

## SHA-256 implementation

- **Files:** `verifier-sdk/src/sha256.c`, `verifier-sdk/src/sha256.h`.
- **Author:** Brad Conte, per the file header.
- **Header:** `verifier-sdk/src/sha256.h:1-7` states `This code is presented "as is" without any guarantees.` It names no license.
- **Upstream:** `https://github.com/B-Con/crypto-algorithms`. Both files are byte-identical to `sha256.c` and `sha256.h` at upstream commit `02b66ec38b474445d10a5d1f0114bc0e8326707e`, the only upstream commit to either file.
- **Route:** public domain. The upstream repository holds no LICENSE file. Its README, added at commit `100f4ff91b5a5b31a84b3999365c3058df6251ea` and unchanged through `cfbde48414baacf51fc7c74f275190881f037d32` (https://github.com/B-Con/crypto-algorithms/blob/100f4ff91b5a5b31a84b3999365c3058df6251ea/README.md), states:

  > This code is released into the public domain free of any restrictions. The author requests acknowledgement if the code is used, but does not require it. This code is provided free of any liability and without any quality claims by the author.

- **What an app must retain:** nothing is required. The author requests acknowledgement; this file carries it.

