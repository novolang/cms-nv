# cms-nv

The Cryptographic Message Syntax (CMS), specified in
[RFC 5652](https://www.rfc-editor.org/rfc/rfc5652), is the format in which a
message is signed, encrypted or digested and the result is written as ASN.1
DER. It is the format inside S/MIME mail, inside code-signing and firmware
signatures, and, as PKCS #7, inside the certificate bags that servers hand
out. This package reads and writes it in novo-lang over
[asn1-nv](https://novo-lang.org/packages/asn1-nv), and takes a signer's
public key from a certificate parsed by
[x509-nv](https://novo-lang.org/packages/x509-nv). The PKCS #12 file, whose
safes are CMS messages, is
[pkcs12-nv](https://novo-lang.org/packages/pkcs12-nv).

## What CMS is

Every CMS message is a **ContentInfo**: an object identifier that names the
content type, and the content. The types here are:

| Content type | What it holds |
| --- | --- |
| `data` | octets, with no protection |
| `signed-data` | content, the certificates and revocation lists the sender chose to include, and one **SignerInfo** per signer |
| `enveloped-data` | content encrypted under a content encryption key (CEK), and for each recipient the CEK in a form only that recipient can open |
| `digested-data` | content and its digest |
| `encrypted-data` | content encrypted under a key the two sides already share |
| `authEnvelopedData` | the enveloped form with an authenticated cipher, AES-GCM (RFC 5083, RFC 5084) |

A **SignerInfo** names the certificate of its signer, by issuer and serial
number or by subject key identifier, names a digest algorithm, and holds the
signature. It usually also holds **signed attributes**: the content type, the
digest of the content (`message-digest`) and often the time. When it does,
the signature covers the DER encoding of the attributes as a SET OF, and not
the content (RFC 5652 section 5.4); the content is bound in through the
message digest. A **RecipientInfo** is one of five kinds: a key transport
(RSA), a key agreement (ECDH), a **KEK** recipient (a key the sender and the
recipient share, wrapped with AES key wrap, RFC 3394), a **password**
recipient (a key derived from a password with PBKDF2 and wrapped as RFC 3211
describes), and an open type.

## Install

```
novo pkg add cms-nv
```

## Example

```novo
use std.bytes
use cmsoid
use cmsenv
use cmsinfo

// Seal a message for the holder of a 16-byte key, and open it again.  The
// content key and the IV are the caller's; this package draws no random
// numbers.
fn round_trip(kek: Bytes, cek: Bytes, iv: Bytes) -> Str
    let target = CmsKekTarget { key_id: bytes.from_str("key-1"), kek: kek }
    match cmsenv.enveloped_write(OID_AES128_CBC, cek, iv, bytes.from_str("hello"), [target], [], false)
        Err(e) => e.message()
        Ok(message) =>
            match cmsenv.enveloped_read(message)
                Err(e) => e.message()
                Ok(m)  =>
                    match cmsenv.decrypt_with_kek(m, bytes.from_str("key-1"), kek, None)
                        Err(e) => e.message()
                        Ok(p)  => bytes.to_str(p)
```

Build and test with:

```
novo pkg build               # type- and effect-check the package
novo test tests --isolate    # the vectors and the refusals
```

## What the package contains

| Module | Contents |
| --- | --- |
| `cmsinfo` | ContentInfo, and the types that need no certificate: `data`, `digested-data` and `encrypted-data`, with the EncryptedContentInfo they share with enveloped-data. |
| `cmssigned` | SignedData: reading, `verify` and `find_certificate`, `sign` for ECDSA and Ed25519, and the certificate-only bag. |
| `cmsenv` | EnvelopedData and AuthEnvelopedData: the five kinds of recipient read, KEK and password recipients opened and written. |
| `cmscrypto` | The digests, AES-CBC with PKCS #7 padding, the RFC 3394 and RFC 3211 key wraps, and AES-GCM. |
| `cmsder` | The DER and BER layer: values in the caller's bytes, and a writer of DER. |
| `cmsoid` | The object identifiers as named constants. |
| `cmserr` | The error type `CmsError`. |

No function reads a clock, draws randomness or performs input or output.

## How to choose an entry point

**To check a signed message,** read it with `cmssigned.read`, choose the
signer, and call `verify_embedded` to use the certificate the message carries
or `verify` with a certificate you hold. `verify` answers the content, so the
bytes a program passes on are the bytes that were checked.

**To open an encrypted message,** read it with `cmsenv.enveloped_read` or
`auth_read` and call `decrypt_with_kek`, `decrypt_with_password` or
`decrypt_with_cek`.

**To look inside a message first,** call `cmsinfo.read`, which answers the
content type and the content value without interpreting it.

## The rules a user needs

1. **A signature is checked against a certificate the caller names.** The
   package does not build a chain, check validity or purposes, or read a
   revocation list. `find_certificate` picks the included certificate a
   SignerInfo names, and that certificate is not trusted by being included.
   x509-nv has the chain tools.
2. **The signed attributes are checked.** The message digest must equal the
   digest of the content, the content type attribute must equal the content's,
   and each appears once with one value (RFC 5652 section 11). The signature
   covers the attributes as received with the tag byte changed to the SET OF
   tag, so a signer that used the indefinite length for them is refused with
   `CmsNotDer`.
3. **BER is read, DER is written.** A message from a streaming encoder uses
   the indefinite length and constructed OCTET STRINGs; both are read.
   Everything written is DER.
4. **Nothing here draws random numbers.** The CEK, the IV, the nonce, the
   PBKDF2 salt and the padding of the RFC 3211 wrap are arguments. A CEK, an
   IV and a nonce must be fresh for every message.
5. **There are two key wraps and they differ.** A KEK recipient names an
   RFC 3394 AES key wrap by its identifier. A password recipient wraps with the
   CBC construction of RFC 3211 section 2.3, with a four-octet header and
   check, whatever cipher its parameter names.
6. **The PBKDF2 count is the sender's.** `decrypt_with_password` takes
   `max_iterations` and refuses a larger count.
7. **AES-GCM is checked before anything is produced.** `CmsAuthFailed` is the
   only answer to a bad tag, a wrong key and a changed ciphertext. CBC has no
   tag; its only check is the padding, and it gives the same answer.
8. **A detached content is passed to the checker,** and a message that carries
   its own content refuses one (`CmsDetachedConflict`).
9. **The Ed25519 digest is SHA-512** (RFC 8419 section 3), and the signature
   covers the DER signed attributes themselves; with no signed attributes it
   covers the content. ECDSA with SHA-384 on P-256 uses the leftmost 256 bits
   of the digest.
10. **A `SignerInfo` that names a certificate by key identifier** is found by
    `find_certificate` only in a certificate that has a subject key identifier
    extension.

## Algorithms

| Algorithm | Direction | Notes |
| --- | --- | --- |
| RSASSA-PKCS1-v1_5, SHA-256 and SHA-384 | verify | rsa-nv; the modulus is 2048 bits or more |
| RSASSA-PSS, SHA-256 and SHA-384 (RFC 4056) | verify | mask hash equal to the hash, salt as long as the hash |
| ECDSA on P-256, SHA-256 and SHA-384 (RFC 5753) | verify and sign | |
| Ed25519 (RFC 8419) | verify and sign | strict verification of ed25519-nv |
| AES-128, AES-192 and AES-256 in CBC mode | encrypt and decrypt | PKCS #7 padding |
| AES-GCM with a 128, 192 or 256-bit key (RFC 5084) | encrypt and decrypt | a 16-byte tag |
| AES key wrap, RFC 3394 | wrap and unwrap | KEK recipients |
| RFC 3211 key wrap, PBKDF2 with HMAC-SHA-1, -256 or -512 | wrap and unwrap | password recipients |
| SHA-1, SHA-256, SHA-384, SHA-512 | digest | digested-data and signed attributes |

## What is not included

- **RSA signing.** rsa-nv verifies RSA signatures and does not make them.
- **RSA with SHA-1 or SHA-512,** which rsa-nv does not verify; and
  RSASSA-PSS with a mask hash that differs from the message hash, or a salt
  length that is not the hash length.
- **KeyTransRecipientInfo and KeyAgreeRecipientInfo.** Both are read, and a
  message that holds one is described by it; opening the RSA key transport
  needs a private-key operation rsa-nv does not have, and the ECDH recipient
  of RFC 5753 is not written. A message with an RSA recipient and a KEK
  recipient opens through the KEK.
- **AuthenticatedData** (RFC 5652 section 9). Its object identifier is named
  and a message of the type is refused as the wrong content type.
- **Countersignatures** (section 11.4). The unsigned attributes are not read.
- **DES-EDE3-CBC and RC2-CBC content encryption.** The registry has neither
  cipher. A message that uses one is refused with the algorithm named.
- **AES-GCM with an ICV length other than 16,** the authenticated attributes
  of AuthEnvelopedData, and the originator information, which is skipped.
- **Chain building, validity, key usage and revocation checks.**
- **A clock and a random number generator.**
- **Signing with RSA, and signing with ECDSA on any curve but P-256.**
- **The embedded tier.** A message is read into lists of nodes and signed
  with `Bytes`, which are heap objects, and the package has no module that
  checks at `@tier(embedded)`. A device that only needs to find the length or
  the content type of a DER value has asn1-nv's `asn1tag`.

## Tests

The OpenSSL vectors were made once on 2026-11-11 with OpenSSL 3.0.13 from a
2048-bit RSA key, a P-256 key and an Ed25519 key in self-signed certificates:
`cms -sign` with RSASSA-PKCS1-v1_5, RSASSA-PSS and ECDSA, `crl2pkcs7` for the
certificate bag, `cms -encrypt` with a KEK recipient, with a password
recipient and with AES-GCM, `-EncryptedData_encrypt` and `-digest_create`.
`tests/generate/gen_cms_vectors.sh` has the commands. OpenSSL 3.0 cannot make
or check an Ed25519 CMS signature, so the Ed25519 messages are made by this
package; RFC 8419 prints no example bytes. In the other direction, OpenSSL
verifies a signed-data and opens the enveloped-data, auth-enveloped-data,
password and KEK messages this package writes, and prints the digested and
encrypted data.

RFC 4134 prints its examples as ASN.1 dumps, with the octet strings in
hexadecimal. Section 3.1 and 3.2 (data, in BER and DER), 6 (digested-data with
SHA-1) and 7.1 (encrypted-data with TripleDES) are written out byte for byte
from the dump and checked against it; the longer signed-data and
enveloped-data examples use 1024-bit RSA and DSA, TripleDES and RC2, none of
which the registry packages run, and are not reproduced.

`tests/cms_content_tests.nv` covers ContentInfo, data, digested-data,
encrypted-data and the primitives (RFC 3394 key wrap vectors included).
`tests/cms_signed_tests.nv` covers the signed-data vectors. `tests/cms_enveloped_tests.nv`
covers the enveloped-data and auth-enveloped-data vectors. `tests/cms_refusal_tests.nv`
covers the refusals with crafted structures. `tests/coverage.sh` measures the
line coverage of `src/`.

## Licence

Apache-2.0. See `LICENSE`.
