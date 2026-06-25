#!/usr/bin/env bash
# Drop into a ROS2 Humble shell for the fm-docker base.
#
# Dispatch is determined by the host OS:
#   macOS  → container (OrbStack; no native ROS2 on macOS)
#   Linux  → bare-metal (native ROS2 at /opt/ros/humble; no container path)
#
# Linux runs native only — there is no container fallback. On the macOS
# container path, --pull forces an image refresh and --build builds
# Dockerfile.base locally.
#
#   ./run.sh [--macos|--linux] [--pull|--build]
#
# OS is auto-detected; --macos / --linux force it.
set -euo pipefail

# Keep the caller's directory: it is the workspace for the bare-metal shell
# and the mount (FM_WS) for the container. The script's own dir holds the
# compose files, so cd there for the container path.
INVOKE_DIR="$PWD"
cd "$(dirname "${BASH_SOURCE[0]}")"

# shellcheck source=scripts/lib.sh
source scripts/lib.sh

IMAGE="ghcr.io/first-motive/fm-docker:humble"
ROS_SETUP="/opt/ros/humble/setup.bash"

OS=""
BUILD=0
PULL_MODE="missing"   # have the image? use it. compose pulls only when absent.
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
  OS=$(detect_os) || exit 1
fi

# --- Linux: bare-metal — source the host ROS2 + workspace overlay, exec a shell ---
if [ "$OS" = "linux" ]; then
  if [ ! -f "$ROS_SETUP" ]; then
    echo "ERROR: Linux needs native ROS2 Humble at /opt/ros/humble; not found." >&2
    echo "       Install ROS2 Humble, or run on macOS for the container path." >&2
    exit 1
  fi
  if [ "$BUILD" -eq 1 ] || [ "$PULL_MODE" != "missing" ]; then
    echo "WARN: --build / --pull apply to the macOS container path; ignored on Linux." >&2
  fi
  echo "Running native ROS2 Humble (bare-metal) in $INVOKE_DIR ..."
  # ROS setup scripts reference unbound vars; relax nounset while sourcing.
  set +u
  # shellcheck source=/dev/null
  source "$ROS_SETUP"
  if [ -f "$INVOKE_DIR/install/setup.bash" ]; then
    # shellcheck source=/dev/null
    source "$INVOKE_DIR/install/setup.bash"
  fi
  set -u
  cd "$INVOKE_DIR"
  exec bash
fi

# --- macOS: container — compose + host overlay ---
export FM_WS="${FM_WS:-$INVOKE_DIR}"   # mount the caller's dir at /ws
OVERLAY="compose.macos.yaml"

if [ "$BUILD" -eq 1 ]; then
  echo "Building Dockerfile.base locally as $IMAGE ..."
  docker build -f Dockerfile.base -t "$IMAGE" .
  PULL_MODE="never"   # use the freshly built image, never pull over it
fi

echo "Starting container shell (overlay: $OVERLAY, pull: $PULL_MODE)..."
exec docker compose -f compose.yaml -f "$OVERLAY" run --pull "$PULL_MODE" --rm fm bash
