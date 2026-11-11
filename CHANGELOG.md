# Changelog

All notable changes to cms-nv are recorded here. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
with the pre-1.0 rule that a breaking change bumps the MINOR number.

## 0.1.0

The Cryptographic Message Syntax, RFC 5652, with RFC 5083 and RFC 5084.

### Added

- ContentInfo, and the content types data, digested-data (SHA-1, SHA-256,
  SHA-384, SHA-512) and encrypted-data (AES-CBC), read as BER or DER and
  written as DER.
- SignedData: reading, the signed attributes checked, verification of
  RSASSA-PKCS1-v1_5 and RSASSA-PSS with SHA-256 and SHA-384, ECDSA on P-256
  and Ed25519, signing with ECDSA and Ed25519 with issuer-and-serial or
  subject-key-identifier signer identifiers, the included certificates found
  and matched to a signer, and the degenerate SignedData that carries
  certificates only.
- EnvelopedData and AuthEnvelopedData: all five kinds of RecipientInfo read,
  KEK recipients (AES key wrap, RFC 3394) and password recipients (PBKDF2 and
  the key wrap of RFC 3211) opened and written, AES-CBC and AES-GCM content.
- The object identifiers as named constants.
- Tests: the byte-for-byte RFC 4134 examples of sections 3.1, 3.2, 6 and 7.1,
  the RFC 3394 key wrap vectors, messages made with OpenSSL 3.0.13, and
  crafted refusals. Messages this package writes are verified and opened by
  OpenSSL. Measured line coverage of `src/` is 100%.

### Known

- Not implemented: RSA signing; RSA with SHA-1 or SHA-512; KeyTransRecipientInfo
  and KeyAgreeRecipientInfo opening (they are read); AuthenticatedData;
  countersignatures; DES-EDE3-CBC and RC2-CBC content; the authenticated
  attributes of AuthEnvelopedData.
- The dependency on asn1-nv is `^0.1.1` because x509-nv 0.1.0 requires it; the
  fixes of asn1-nv 0.2.0 concern the byte-at-a-time scanners this package does
  not use.

This release requires novo 0.24.1 or later.
