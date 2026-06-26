#!/usr/bin/env bash
# fm-docker host installer (macOS only). Brings a Mac to the point it can run
# the First Motive ROS2 base image: installs and starts OrbStack, then pulls the
# base image locally. Idempotent — safe to re-run.
#
# Linux is not handled here — it runs ROS2 Humble natively (see run.sh), with no
# container runtime to install.
#
# Curl-able (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/first-motive/fm-docker/v0.1.0/install.sh | bash
#
# From a clone:
#   ./install.sh [--no-pull]
#
# --no-pull sets up the runtime only and skips the image pull.
set -euo pipefail

IMAGE="ghcr.io/first-motive/fm-docker:humble"
# fm-docker serves its own helper scripts; lib.sh is owned by fm-tools and
# fetched from a pinned release tag (the single reuse home).
RAW_BASE="https://raw.githubusercontent.com/first-motive/fm-docker/v0.1.0"
FM_TOOLS_RAW="https://raw.githubusercontent.com/first-motive/fm-tools/v0.2.0"

# Resolve the script's own dir (empty when piped via curl|bash).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""

# Load the shared bootstrap library from fm-tools. fm-docker no longer vendors
# lib.sh — it lives in fm-tools and is fetched from a pinned tag. The functions
# must run in this shell, so eval the captured fetch — not source <(...), which
# needs /dev/fd, absent when bash reads this script from a curl|bash pipe.
# Capture and validate first: eval of an empty/failed fetch is a silent no-op
# that surfaces later as a confusing "fm_detect_os: command not found".
lib="$(curl -fsSL --proto '=https' --proto-redir '=https' "$FM_TOOLS_RAW/lib.sh")" \
  || { echo "ERROR: failed to fetch lib.sh from fm-tools" >&2; exit 1; }
[ -n "$lib" ] || { echo "ERROR: empty lib.sh download" >&2; exit 1; }
eval "$lib"

PULL=1
for arg in "$@"; do
  case "$arg" in
    --no-pull) PULL=0 ;;
    *) echo "ERROR: unknown flag: $arg" >&2; exit 2 ;;
  esac
done

OS=$(fm_detect_os) || exit 1

# CI self-test hook: deps loaded and OS resolved — stop before any host changes.
# Lets the macOS curl-path test exercise the piped fetch without installing.
if [ -n "${FM_SELFTEST:-}" ]; then
  echo "selftest ok: lib loaded, os=$OS"
  exit 0
fi

if [ "$OS" != "macos" ]; then
  echo "ERROR: install.sh is macOS-only; Linux runs ROS2 Humble natively (see run.sh)." >&2
  exit 1
fi

# Fetch + run an action script: from the clone if present, else over the network.
run_helper() {
  local name="$1"
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/scripts/$name" ]; then
    bash "$SCRIPT_DIR/scripts/$name"
  else
    curl -fsSL "$RAW_BASE/scripts/$name" | bash
  fi
}

install_macos() {
  run_helper install-orbstack.sh
  run_helper ensure-docker.sh
}

pull_image() {
  if ! fm_has_docker; then
    echo "WARN: docker unavailable — skipping image pull" >&2
    return 0
  fi
  echo "Pulling $IMAGE ..."
  docker pull "$IMAGE" || echo "WARN: pull failed — pull later: docker pull $IMAGE" >&2
}

echo "fm-docker install (macOS) ..."
install_macos
if [ "$PULL" -eq 1 ]; then
  pull_image
fi
echo "Done."
