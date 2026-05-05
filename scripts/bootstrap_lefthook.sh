#!/usr/bin/env bash
set -euo pipefail
VERSION=1.7.10
os_lower=$(uname -s | tr '[:upper:]' '[:lower:]')
OS=$(echo "$os_lower" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
ARCH=$(uname -m | sed 's/x86_64/x86_64/;s/aarch64/arm64/')
DEST=.bin/lefthook
mkdir -p .bin
curl -sSfL "https://github.com/evilmartians/lefthook/releases/download/v${VERSION}/lefthook_${VERSION}_${OS}_${ARCH}" -o "$DEST"
chmod +x "$DEST"
"$DEST" install
echo "lefthook $VERSION installed and hooks configured"
