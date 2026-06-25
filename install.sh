#!/usr/bin/env bash
# fm-docker host installer. Brings a host to the point it can run the First
# Motive ROS2 base image: a container runtime, plus the base image pulled
# locally. Idempotent — safe to re-run.
#
# Curl-able (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/first-motive/fm-docker/main/install.sh | bash
#
# From a clone:
#   ./install.sh [--macos|--linux] [--no-pull]
#
# OS is auto-detected; --macos / --linux force a path. --no-pull sets up the
# runtime only and skips the image pull.
set -euo pipefail

IMAGE="ghcr.io/first-motive/fm-docker:humble"
RAW_BASE="https://raw.githubusercontent.com/first-motive/fm-docker/main"

OS=""
PULL=1
for arg in "$@"; do
  case "$arg" in
    --macos) OS="macos" ;;
    --linux) OS="linux" ;;
    --no-pull) PULL=0 ;;
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

# Resolve the helper-script source. A clone runs them from scripts/; a piped
# install (BASH_SOURCE is not a real path) fetches them from the raw repo.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || true)"
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

# Linux runtime is host-managed (Docker Engine, NVIDIA toolkit, X11). Report
# what is present and point at the fix for what is missing; never hard-fail —
# CPU-only, headless hosts are valid for dev and sim.
check_linux() {
  if command -v docker >/dev/null 2>&1; then
    echo "docker:  $(docker --version)"
  else
    echo "WARN: docker not found — install Docker Engine: https://docs.docker.com/engine/install/" >&2
  fi
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo "nvidia:  GPU driver present"
  else
    echo "WARN: nvidia-smi not found — GPU passthrough unavailable (CPU-only is fine for dev/sim)" >&2
  fi
  if command -v xhost >/dev/null 2>&1; then
    echo "xhost:   present (X11 GUI passthrough available)"
  else
    echo "WARN: xhost not found — install x11-xserver-utils for rviz/GUI passthrough" >&2
  fi
}

pull_image() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "WARN: docker unavailable — skipping image pull" >&2
    return 0
  fi
  echo "Pulling $IMAGE ..."
  docker pull "$IMAGE" || echo "WARN: pull failed — pull later: docker pull $IMAGE" >&2
}

echo "fm-docker install — OS: $OS"
case "$OS" in
  macos) install_macos ;;
  linux) check_linux ;;
esac
[ "$PULL" -eq 1 ] && pull_image
echo "Done."
