#!/usr/bin/env bash
# fm-docker host installer (macOS only). Brings a Mac to the point it can run
# the First Motive ROS2 base image: installs and starts OrbStack, then pulls the
# base image locally. Idempotent — safe to re-run.
#
# Linux is not handled here — it runs ROS2 Humble natively (see run.sh), with no
# container runtime to install.
#
# Curl-able (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/first-motive/fm-docker/main/install.sh | bash
#
# From a clone:
#   ./install.sh [--no-pull]
#
# --no-pull sets up the runtime only and skips the image pull.
set -euo pipefail

IMAGE="ghcr.io/first-motive/fm-docker:humble"
RAW_BASE="https://raw.githubusercontent.com/first-motive/fm-docker/main"

# Resolve the script's own dir (empty when piped via curl|bash).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""

# Load the shared host checks: from the clone if present, else fetch them —
# install.sh is itself curl|bash-able, so the library may not be on disk. The
# checks must run in this shell, so source rather than execute.
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/scripts/lib.sh" ]; then
  # shellcheck source=scripts/lib.sh
  source "$SCRIPT_DIR/scripts/lib.sh"
else
  # shellcheck disable=SC1090
  source <(curl -fsSL "$RAW_BASE/scripts/lib.sh")
fi

PULL=1
for arg in "$@"; do
  case "$arg" in
    --no-pull) PULL=0 ;;
    *) echo "ERROR: unknown flag: $arg" >&2; exit 2 ;;
  esac
done

OS=$(detect_os) || exit 1
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
  if ! has_docker; then
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
