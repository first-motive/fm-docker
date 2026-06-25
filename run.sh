#!/usr/bin/env bash
# Drop into an interactive shell in the fm-docker base image, through compose
# plus the host overlay. Pulls the published :humble tag by default; --build
# builds Dockerfile.base locally instead.
#
#   ./run.sh [--macos|--linux] [--build]
#
# OS is auto-detected; --macos / --linux force the overlay.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

IMAGE="ghcr.io/first-motive/fm-docker:humble"

OS=""
BUILD=0
for arg in "$@"; do
  case "$arg" in
    --macos) OS="macos" ;;
    --linux) OS="linux" ;;
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
else
  echo "Pulling $IMAGE ..."
  docker pull "$IMAGE"
fi

echo "Starting interactive shell (overlay: $OVERLAY)..."
exec "${COMPOSE[@]}" run --rm fm bash
