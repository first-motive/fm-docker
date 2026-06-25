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

# Resolve the script's own dir (empty when piped via curl|bash).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || true)"

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
  OS=$(detect_os) || exit 1
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

# Linux runtime is host-managed (Docker Engine, NVIDIA toolkit, X11). Report
# what is present and point at the fix for what is missing; never hard-fail —
# CPU-only, headless hosts are valid for dev and sim.
check_linux() {
  if has_docker; then
    echo "docker:  $(docker --version)"
  else
    echo "WARN: docker not found — install Docker Engine: https://docs.docker.com/engine/install/" >&2
  fi
  if has_gpu; then
    echo "nvidia:  usable GPU present"
  else
    echo "WARN: no usable NVIDIA GPU — GPU passthrough unavailable (CPU-only is fine for dev/sim)" >&2
  fi
  if has_xhost; then
    echo "xhost:   present (X11 GUI passthrough available)"
  else
    echo "WARN: xhost not found — install x11-xserver-utils for rviz/GUI passthrough" >&2
  fi
}

pull_image() {
  if ! has_docker; then
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
if [ "$PULL" -eq 1 ]; then
  pull_image
fi
echo "Done."
