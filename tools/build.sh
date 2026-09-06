#!/bin/zsh
# Build the watchApp for venu445mm.
#
# The SDK is not on PATH and the signing key is a throwaway self-signed one
# (the app is a personal sideload, never store-published), so both are
# resolved here rather than assumed. Override either with an env var.
#
# Usage: tools/build.sh [-r]        # -r builds release; default is debug
set -e
SDK="${CIQ_SDK:-$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2}"
KEY="${CIQ_KEY:-$(dirname $0)/../.scratch/keys/developer_key.der}"
ROOT="${0:A:h:h}"
OUT="${ROOT}/build/dtector.prg"

[[ -f "$KEY" ]] || {
  echo "no signing key at $KEY -- generate one with:" >&2
  echo "  openssl genrsa -out dev.pem 4096 && \\" >&2
  echo "  openssl pkcs8 -topk8 -inform PEM -outform DER -in dev.pem -out developer_key.der -nocrypt" >&2
  exit 2
}

"$SDK/bin/monkeyc" -f "$ROOT/app/monkey.jungle" -o "$OUT" -y "$KEY" \
  -d venu445mm -w --build-stats 0 "$@"
echo "built $OUT ($(stat -f%z "$OUT") bytes)"
