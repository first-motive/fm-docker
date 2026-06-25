#!/usr/bin/env bash
# Drop into a ROS2 Humble shell for the fm-docker base.
#
# Dispatch (the container is macOS-first; Linux prefers native ROS2):
#   macOS                    → container (no native ROS2 path)
#   Linux + /opt/ros/humble  → bare-metal (native, fast, no docker)
#   Linux, no Humble         → container (run-anywhere fallback)
#
# Force a path with --container (always docker) or --local (always bare-metal,
# Linux only). On the container path, --pull forces an image refresh and --build
# builds Dockerfile.base locally.
#
#   ./run.sh [--macos|--linux] [--container|--local] [--pull|--build]
#
# OS is auto-detected; --macos / --linux force the overlay.
set -euo pipefail

# Keep the caller's directory: it is the workspace for the bare-metal overlay
# and the mount (FM_WS) for the container. The script's own dir holds the
# compose files, so cd there for the container path.
INVOKE_DIR="$PWD"
cd "$(dirname "${BASH_SOURCE[0]}")"

IMAGE="ghcr.io/first-motive/fm-docker:humble"
ROS_SETUP="/opt/ros/humble/setup.bash"

OS=""
MODE=""               # "", container, local — empty means auto-resolve
BUILD=0
PULL_MODE="missing"   # have the image? use it. compose pulls only when absent.
for arg in "$@"; do
  case "$arg" in
    --macos) OS="macos" ;;
    --linux) OS="linux" ;;
    --container) MODE="container" ;;
    --local) MODE="local" ;;
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

# Resolve the mode when not forced: macOS always uses the container; Linux runs
# native Humble when the host has it, else falls back to the container.
if [ -z "$MODE" ]; then
  if [ "$OS" = "linux" ] && [ -d /opt/ros/humble ]; then
    MODE="local"
  else
    MODE="container"
  fi
fi

# --- bare-metal path: source the host ROS2 + workspace overlay, exec a shell ---
if [ "$MODE" = "local" ]; then
  if [ "$OS" = "macos" ]; then
    echo "ERROR: --local needs native ROS2; macOS has none. Drop --local to use the container." >&2
    exit 1
  fi
  if [ ! -f "$ROS_SETUP" ]; then
    echo "ERROR: --local needs ROS2 Humble at /opt/ros/humble; not found. Drop --local to use the container." >&2
    exit 1
  fi
  if [ "$BUILD" -eq 1 ] || [ "$PULL_MODE" != "missing" ]; then
    echo "WARN: --build / --pull apply to the container path; ignored for bare-metal." >&2
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

# --- container path: compose + host overlay ---
export FM_WS="${FM_WS:-$INVOKE_DIR}"   # mount the caller's dir at /ws
OVERLAY="compose.${OS}.yaml"

if [ "$BUILD" -eq 1 ]; then
  echo "Building Dockerfile.base locally as $IMAGE ..."
  docker build -f Dockerfile.base -t "$IMAGE" .
  PULL_MODE="never"   # use the freshly built image, never pull over it
fi

echo "Starting container shell (overlay: $OVERLAY, pull: $PULL_MODE)..."
exec docker compose -f compose.yaml -f "$OVERLAY" run --pull "$PULL_MODE" --rm fm bash
