#!/bin/bash
# Makes the code signing certificate "Yaseen Local Signing" in your login keychain.
#
# USAGE:
#   scripts/make-signing-cert.sh
#
# Run it one time on the Mac that builds the app. scripts/bundle.sh then signs
# the app with this certificate, and macOS keeps the Screen Recording permission
# after an update. The certificate is self-signed and free. It is valid for 10 years.
#
# The script changes your login keychain. For that reason the owner of the Mac
# runs it, not an agent.
set -euo pipefail

NAME="Yaseen Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -F "\"$NAME\"" >/dev/null; then
    echo "The certificate \"$NAME\" is already in your login keychain. Nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# The password protects the file only for the seconds between the two commands below.
PASSWORD="$(/usr/bin/openssl rand -hex 16)"

# /usr/bin/openssl is the LibreSSL of macOS. Its .p12 format is the one that `security` reads.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

/usr/bin/openssl pkcs12 -export -name "$NAME" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/cert.p12" -passout "pass:$PASSWORD"

# -T lets codesign use the key. macOS can still ask one time; then click "Always Allow".
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null

if security find-identity -p codesigning "$KEYCHAIN" | grep -F "\"$NAME\"" >/dev/null; then
    echo "Done. The certificate \"$NAME\" is in your login keychain."
else
    echo "error: the certificate is not in the keychain after the import." >&2
    exit 1
fi
