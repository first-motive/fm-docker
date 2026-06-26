#!/usr/bin/env bash
# Drop into a ROS2 Humble shell for the fm-docker base.
#
# Curl-able (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/first-motive/fm-docker/v0.1.0/run.sh | bash
#
# From a clone:
#   ./run.sh [--macos|--linux] [--pull|--build] [-h|--help]
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
# OS is auto-detected; --macos / --linux force it. The body is wrapped in main()
# and called on the last line, so a truncated curl|bash never half-runs.
set -euo pipefail

IMAGE="ghcr.io/first-motive/fm-docker:humble"
ROS_SETUP="/opt/ros/humble/setup.bash"
# fm-docker serves its own compose files + helper scripts; lib.sh is owned by
# fm-tools and fetched from a pinned release tag (the single reuse home).
RAW_BASE="https://raw.githubusercontent.com/first-motive/fm-docker/v0.1.0"
FM_TOOLS_RAW="https://raw.githubusercontent.com/first-motive/fm-tools/v0.2.0"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/fm-docker"

# Keep the caller's directory: it is the workspace for the bare-metal shell and
# the mount (FM_WS) for the container.
INVOKE_DIR="$PWD"

# Resolve the script's own dir; empty when piped via curl|bash. A clone has the
# repo files next to the script (REPO_DIR set); a piped run does not (REPO_DIR
# empty), so deps are fetched from RAW_BASE instead.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/compose.yaml" ]; then
  REPO_DIR="$SCRIPT_DIR"
else
  REPO_DIR=""
fi

# Load the shared bootstrap library from fm-tools. fm-docker no longer vendors
# lib.sh — it lives in fm-tools and is fetched from a pinned tag. The functions
# must run in this shell, so eval the captured fetch — not source <(...), which
# needs /dev/fd, absent when bash reads this script from a curl|bash pipe.
# Capture and validate first: eval of an empty/failed fetch is a silent no-op
# that surfaces later as a confusing "fm_detect_os: command not found".
fm_load_lib() {
  local lib
  lib="$(curl -fsSL --proto '=https' --proto-redir '=https' "$FM_TOOLS_RAW/lib.sh")" \
    || { echo "ERROR: failed to fetch lib.sh from fm-tools" >&2; exit 1; }
  [ -n "$lib" ] || { echo "ERROR: empty lib.sh download" >&2; exit 1; }
  eval "$lib"
}

usage() {
  cat <<'EOF'
run.sh — open a ROS2 Humble shell for the fm-docker base

Usage: ./run.sh [--macos|--linux] [--pull|--build] [-h|--help]

  --macos      force the macOS container path
  --linux      force the Linux bare-metal path
  --pull       macOS: force an image refresh
  --build      macOS: build Dockerfile.base locally (clone only)
  -h, --help   show this help

Env: FM_SELFTEST=1  load deps + resolve OS, then stop before any runtime work.
EOF
}

# macOS container path: bring up a runtime, locate compose, exec the shell.
run_macos() {
  local build="$1" pull_mode="$2"

  # --build needs the Dockerfile on disk, so it is a clone-only flag.
  if [ "$build" -eq 1 ] && [ -z "$REPO_DIR" ]; then
    echo "ERROR: --build needs the repo on disk (Dockerfile.base); clone to build." >&2
    return 2
  fi

  # Bring up a runtime if none is present: install + start OrbStack via install.sh.
  if ! fm_has_docker; then
    echo "No container runtime found — setting up OrbStack ..."
    if [ -n "$REPO_DIR" ]; then
      bash "$REPO_DIR/install.sh" --no-pull
    else
      curl -fsSL --proto '=https' --proto-redir '=https' "$RAW_BASE/install.sh" | bash -s -- --no-pull
    fi
    fm_has_docker || { echo "ERROR: container runtime still unavailable after setup." >&2; return 1; }
  fi

  # Locate the compose files: the clone has them; otherwise cache them locally,
  # fetched once and reused offline. --pull refreshes the cached copies.
  local compose_dir f tmp
  if [ -n "$REPO_DIR" ]; then
    compose_dir="$REPO_DIR"
  else
    compose_dir="$CACHE_DIR"
    mkdir -p "$compose_dir"
    for f in compose.yaml compose.macos.yaml; do
      if [ ! -f "$compose_dir/$f" ] || [ "$pull_mode" = "always" ]; then
        # Fetch to a temp file and rename only on success: an interrupted download
        # must never leave a partial file that later runs treat as cached.
        tmp="$compose_dir/$f.tmp.$$"
        curl -fsSL --proto '=https' --proto-redir '=https' "$RAW_BASE/$f" -o "$tmp" \
          || { rm -f "$tmp"; echo "ERROR: failed to fetch $f" >&2; return 1; }
        [ -s "$tmp" ] || { rm -f "$tmp"; echo "ERROR: empty download of $f" >&2; return 1; }
        mv "$tmp" "$compose_dir/$f"
      fi
    done
  fi

  export FM_WS="${FM_WS:-$INVOKE_DIR}"   # mount the caller's dir at /ws

  if [ "$build" -eq 1 ]; then
    echo "Building Dockerfile.base locally as $IMAGE ..."
    docker build -f "$REPO_DIR/Dockerfile.base" -t "$IMAGE" "$REPO_DIR"
    pull_mode="never"   # use the freshly built image, never pull over it
  fi

  echo "Starting container shell (pull: $pull_mode)..."
  # curl | bash leaves fd 0 on the piped script, not the terminal, so the
  # container shell would read EOF and exit at once — no interactive prompt.
  # Reattach the controlling terminal when one exists; otherwise keep the
  # inherited stdin (no tty, e.g. CI).
  local shell_stdin=/dev/stdin
  { : < /dev/tty; } 2>/dev/null && shell_stdin=/dev/tty
  exec docker compose -f "$compose_dir/compose.yaml" -f "$compose_dir/compose.macos.yaml" \
    run --pull "$pull_mode" --rm fm bash < "$shell_stdin"
}

# Linux bare-metal path: source host ROS2 + workspace overlay, exec a shell.
run_linux() {
  local build="$1" pull_mode="$2"
  if [ ! -f "$ROS_SETUP" ]; then
    echo "ERROR: Linux needs native ROS2 Humble at /opt/ros/humble; not found." >&2
    echo "       Install ROS2 Humble, or run on macOS for the container path." >&2
    return 1
  fi
  if [ "$build" -eq 1 ] || [ "$pull_mode" != "missing" ]; then
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
}

main() {
  local os="" build=0 pull_mode="missing" arg
  for arg in "$@"; do
    case "$arg" in
      --macos) os="macos" ;;
      --linux) os="linux" ;;
      --pull) pull_mode="always" ;;
      --build) build=1 ;;
      -h|--help) usage; return 0 ;;
      *) echo "ERROR: unknown flag: $arg" >&2; usage; return 2 ;;
    esac
  done

  fm_load_lib

  if [ -z "$os" ]; then
    os=$(fm_detect_os) || return 1
  fi

  # CI self-test hook: deps loaded and OS resolved — stop before any runtime work.
  # Lets the macOS curl-path test exercise the piped fetch without OrbStack.
  if [ -n "${FM_SELFTEST:-}" ]; then
    echo "selftest ok: lib loaded, os=$os"
    return 0
  fi

  case "$os" in
    linux) run_linux "$build" "$pull_mode" ;;
    macos) run_macos "$build" "$pull_mode" ;;
  esac
}

main "$@"
