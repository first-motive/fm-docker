#!/usr/bin/env bash
# Drop into a ROS2 Humble shell for the fm-docker base.
#
# Curl-able (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/first-motive/fm-docker/main/run.sh | bash
#
# From a clone:
#   ./run.sh [--macos|--linux] [--pull|--build]
#
# Dispatch is determined by the host OS:
#   macOS  → container (OrbStack, auto-installed if missing; no native ROS2)
#   Linux  → bare-metal (native ROS2 at /opt/ros/humble; no container path)
#
# Linux runs native only — there is no container fallback. On the macOS
# container path, --pull forces an image refresh and --build builds
# Dockerfile.base locally (--build needs a clone). Piped via curl, lib.sh and
# the compose files are cached under ~/.cache/fm-docker and reused offline.
#
# OS is auto-detected; --macos / --linux force it.
set -euo pipefail

IMAGE="ghcr.io/first-motive/fm-docker:humble"
ROS_SETUP="/opt/ros/humble/setup.bash"
RAW_BASE="https://raw.githubusercontent.com/first-motive/fm-docker/main"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/fm-docker"

# Keep the caller's directory: it is the workspace for the bare-metal shell and
# the mount (FM_WS) for the container.
INVOKE_DIR="$PWD"

# Resolve the script's own dir; empty when piped via curl|bash. A clone has the
# repo files next to the script (REPO_DIR set); a piped run does not (REPO_DIR
# empty), so deps are fetched from RAW_BASE instead.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/scripts/lib.sh" ]; then
  REPO_DIR="$SCRIPT_DIR"
else
  REPO_DIR=""
fi

# Load the shared host checks: from the clone if present, else fetch them. The
# checks must run in this shell, so source rather than execute.
if [ -n "$REPO_DIR" ]; then
  # shellcheck source=scripts/lib.sh
  source "$REPO_DIR/scripts/lib.sh"
else
  # eval, not source <(...): process substitution needs /dev/fd, which does not
  # resolve when bash reads this script from a stdin pipe (curl | bash), leaving
  # the lib functions undefined. eval "$(...)" captures into a string instead.
  # Capture and validate first: eval of an empty/failed fetch is a silent no-op
  # that surfaces later as a confusing "detect_os: command not found".
  lib="$(curl -fsSL "$RAW_BASE/scripts/lib.sh")" || { echo "ERROR: failed to fetch lib.sh" >&2; exit 1; }
  [ -n "$lib" ] || { echo "ERROR: empty lib.sh download" >&2; exit 1; }
  eval "$lib"
fi

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

# CI self-test hook: deps loaded and OS resolved — stop before any runtime work.
# Lets the macOS curl-path test exercise the piped fetch without OrbStack.
if [ -n "${FM_SELFTEST:-}" ]; then
  echo "selftest ok: lib loaded, os=$OS"
  exit 0
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

# --- macOS: container ---
# --build needs the Dockerfile on disk, so it is a clone-only flag.
if [ "$BUILD" -eq 1 ] && [ -z "$REPO_DIR" ]; then
  echo "ERROR: --build needs the repo on disk (Dockerfile.base); clone to build." >&2
  exit 2
fi

# Bring up a runtime if none is present: install + start OrbStack via install.sh.
if ! has_docker; then
  echo "No container runtime found — setting up OrbStack ..."
  if [ -n "$REPO_DIR" ]; then
    bash "$REPO_DIR/install.sh" --no-pull
  else
    curl -fsSL "$RAW_BASE/install.sh" | bash -s -- --no-pull
  fi
  has_docker || { echo "ERROR: container runtime still unavailable after setup." >&2; exit 1; }
fi

# Locate the compose files: the clone has them; otherwise cache them locally,
# fetched once and reused offline. --pull refreshes the cached copies.
if [ -n "$REPO_DIR" ]; then
  COMPOSE_DIR="$REPO_DIR"
else
  COMPOSE_DIR="$CACHE_DIR"
  mkdir -p "$COMPOSE_DIR"
  for f in compose.yaml compose.macos.yaml; do
    if [ ! -f "$COMPOSE_DIR/$f" ] || [ "$PULL_MODE" = "always" ]; then
      # Fetch to a temp file and rename only on success: an interrupted download
      # must never leave a partial file that later runs treat as cached.
      tmp="$COMPOSE_DIR/$f.tmp.$$"
      curl -fsSL "$RAW_BASE/$f" -o "$tmp" || { rm -f "$tmp"; echo "ERROR: failed to fetch $f" >&2; exit 1; }
      [ -s "$tmp" ] || { rm -f "$tmp"; echo "ERROR: empty download of $f" >&2; exit 1; }
      mv "$tmp" "$COMPOSE_DIR/$f"
    fi
  done
fi

export FM_WS="${FM_WS:-$INVOKE_DIR}"   # mount the caller's dir at /ws

if [ "$BUILD" -eq 1 ]; then
  echo "Building Dockerfile.base locally as $IMAGE ..."
  docker build -f "$REPO_DIR/Dockerfile.base" -t "$IMAGE" "$REPO_DIR"
  PULL_MODE="never"   # use the freshly built image, never pull over it
fi

echo "Starting container shell (pull: $PULL_MODE)..."
# curl | bash leaves fd 0 on the piped script, not the terminal, so the
# container shell would read EOF and exit at once — no interactive prompt.
# Reattach the controlling terminal when one exists; otherwise keep the
# inherited stdin (no tty, e.g. CI).
SHELL_STDIN=/dev/stdin
{ : < /dev/tty; } 2>/dev/null && SHELL_STDIN=/dev/tty
exec docker compose -f "$COMPOSE_DIR/compose.yaml" -f "$COMPOSE_DIR/compose.macos.yaml" \
  run --pull "$PULL_MODE" --rm fm bash < "$SHELL_STDIN"
