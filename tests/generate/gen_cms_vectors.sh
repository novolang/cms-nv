#!/usr/bin/env bash
# tests/generate/gen_cms_vectors.sh — regenerate the OpenSSL vectors the
# suites hold.  They were made once, on 2026-11-11, with
#
#   OpenSSL 3.0.13 30 Jan 2024
#
# and checked into the suites as hex.  This script writes the same kinds of
# messages into a directory and prints each as a `fn name() -> Str` hex
# function on standard output; the certificates and keys differ on every
# run, so a regenerated file is a new set of vectors, not the same bytes.
#
# usage: bash tests/generate/gen_cms_vectors.sh WORKDIR
set -euo pipefail
D="${1:?a work directory}"
mkdir -p "$D"
cd "$D"
printf 'Hello, CMS world.\n' > msg.txt
openssl req -x509 -newkey rsa:2048 -nodes -keyout rsa.key -out rsa.pem -subj "/CN=cms-nv rsa test" -days 36500 -sha256 2>/dev/null
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout ec.key -out ec.pem -subj "/CN=cms-nv ec test" -days 36500 -sha256 2>/dev/null
# SignedData, RSASSA-PKCS1-v1_5 with SHA-256, the certificate included.
openssl cms -sign -in msg.txt -signer rsa.pem -inkey rsa.key -outform DER -nodetach -md sha256 -out rsa_pkcs1.der
# SignedData, RSASSA-PSS with SHA-256 and a 32-byte salt (RFC 4056).
openssl cms -sign -in msg.txt -signer rsa.pem -inkey rsa.key -outform DER -nodetach -md sha256 \
  -keyopt rsa_padding_mode:pss -keyopt rsa_pss_saltlen:32 -keyopt rsa_mgf1_md:sha256 -out rsa_pss.der
# SignedData, ECDSA P-256 with SHA-256 (RFC 5753).
openssl cms -sign -in msg.txt -signer ec.pem -inkey ec.key -outform DER -nodetach -md sha256 -out ec.der
# SignedData with the content detached.
openssl cms -sign -in msg.txt -signer ec.pem -inkey ec.key -outform DER -md sha256 -out ec_detached.der
# The degenerate SignedData of the PKCS #7 certificate bag.
openssl crl2pkcs7 -nocrl -certfile ec.pem -certfile rsa.pem -outform DER -out certs_only.der
# EnvelopedData: a KeyTransRecipientInfo and a KEKRecipientInfo.
K=000102030405060708090a0b0c0d0e0f
openssl cms -encrypt -in msg.txt -aes-128-cbc -secretkey "$K" -secretkeyid 4b4b4b4b -outform DER -out kek128.der -recip rsa.pem
# EnvelopedData with a PasswordRecipientInfo.
openssl cms -encrypt -in msg.txt -aes-128-cbc -pwri_password 'correct horse' -outform DER -out pwri.der -recip rsa.pem
# AuthEnvelopedData with AES-128-GCM (RFC 5083, RFC 5084).
openssl cms -encrypt -in msg.txt -aes-128-gcm -secretkey "$K" -secretkeyid 4b4b -outform DER -out authenv.der -recip rsa.pem
# EncryptedData with AES-256-CBC.
openssl cms -EncryptedData_encrypt -in msg.txt -aes-256-cbc \
  -secretkey 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f -outform DER -out encdata.der
# DigestedData with SHA-256.
openssl cms -digest_create -in msg.txt -md sha256 -outform DER -out digested.der
for f in rsa_pkcs1 rsa_pss ec ec_detached certs_only kek128 pwri authenv encdata digested; do
  printf 'fn %s() -> Str\n    "%s"\n\n' "$f" "$(xxd -p "$f.der" | tr -d '\n')"
done
for f in rsa ec; do
  openssl x509 -in "$f.pem" -outform DER | xxd -p | tr -d '\n' | { printf 'fn cert_%s() -> Str\n    "' "$f"; cat; printf '"\n\n'; }
done
