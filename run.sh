#!/usr/bin/env bash
# Drop into an interactive shell in the fm-docker base image, through compose
# plus the host overlay. Uses the local :humble image when present and only
# pulls when it is missing — the base rarely changes, so this keeps re-entry
# fast and works offline. --pull forces a refresh; --build builds
# Dockerfile.base locally instead.
#
#   ./run.sh [--macos|--linux] [--pull|--build]
#
# OS is auto-detected; --macos / --linux force the overlay.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

IMAGE="ghcr.io/first-motive/fm-docker:humble"

OS=""
BUILD=0
PULL_MODE="missing"   # have it? use it. compose pulls only when absent.
for arg in "$@"; do
  case "$arg" in
    --macos) OS="macos" ;;
    --linux) OS="linux" ;;
    --pull) PULL_MODE="always" ;;
    --build) BUILD=1 ;;
    *) echo "ERROR: unknown flag: $arg" >&2; exit 2 ;;
  esac
done

if [ -z "$OS" ]; then
  case "$(uname -s)" in
    Darwin) OS="macos" ;;
    Linux) OS="linux" ;;
    *) echo "ERROR: unsupported OS: $(uname -s)" >&2; exit 1 ;;
  esac
fi

OVERLAY="compose.${OS}.yaml"
COMPOSE=(docker compose -f compose.yaml -f "$OVERLAY")

if [ "$BUILD" -eq 1 ]; then
  echo "Building Dockerfile.base locally as $IMAGE ..."
  docker build -f Dockerfile.base -t "$IMAGE" .
  PULL_MODE="never"   # use the freshly built image, never pull over it
fi

echo "Starting interactive shell (overlay: $OVERLAY, pull: $PULL_MODE)..."
exec "${COMPOSE[@]}" run --pull "$PULL_MODE" --rm fm bash
