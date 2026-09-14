#!/usr/bin/env bash
# Convenience wrapper around `docker build`.
#
# Usage:
#   ./scripts/build.sh                          # default: BUILD_MODE=bundle
#   ./scripts/build.sh source                   # rebuild from source
#   ./scripts/build.sh bundle myname v1.0       # custom tag
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-bundle}"
TAG="${2:-locateanything-server}"
VERSION="${3:-cuda}"

case "$MODE" in
    bundle|source) ;;
    *) echo "usage: $0 [bundle|source] [tag] [version]" >&2; exit 2 ;;
esac

echo "[$(date)] docker build --build-arg BUILD_MODE=$MODE -t $TAG:$VERSION ."
docker build --build-arg "BUILD_MODE=$MODE" -t "$TAG:$VERSION" .
echo "[$(date)] built $TAG:$VERSION"
docker images "$TAG:$VERSION"