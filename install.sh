#!/usr/bin/env bash
# fm-docker host installer (macOS only). Brings a Mac to the point it can run
# the First Motive ROS2 base image: installs and starts OrbStack, then pulls the
# base image locally. Idempotent — safe to re-run.
#
# Linux is not handled here — it runs ROS2 Humble natively (see run.sh), with no
# container runtime to install.
#
# Curl-able (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/first-motive/fm-docker/v0.1.3/install.sh | bash
#
# Inspect before running (always offer this path):
#   curl -fsSL https://raw.githubusercontent.com/first-motive/fm-docker/v0.1.3/install.sh -o install.sh
#   less install.sh && bash install.sh
#
# From a clone:
#   ./install.sh [install|uninstall] [--no-pull] [--dry-run] [-y] [-h]
#
# --no-pull sets up the runtime only and skips the image pull. uninstall removes
# the pulled image and leaves OrbStack (a shared app we did not exclusively own).
# The body is wrapped in main() and called on the last line, so a truncated
# curl|bash leaves an incomplete function that never runs.
set -euo pipefail

# The image this installer pre-pulls, pinned by digest so it is the same one
# compose.yaml runs. Pulling :humble instead would seed the host with whatever
# main built last, which compose would then pull over on the first run. Keep
# this digest equal to the one in compose.yaml — the README has the bump flow.
IMAGE="ghcr.io/first-motive/fm-docker@sha256:68afd2d27c590ffe63809f7a088eb791eed6ba74b280e4e260a9795a66981766"
# fm-docker serves its own helper scripts from its own release tag. That tag is
# a literal here because a curl|bash run has no clone to read it from;
# scripts/check-tag-refs.sh holds every such literal to the rendered pin.
RAW_BASE="https://raw.githubusercontent.com/first-motive/fm-docker/v0.1.3"
# fm-render:begin fm-tools-pin sha256:5de9c0a921c441407f1aea8b6e32f37ca9d3f654d1116c636f0a7136da03b7d2 — rendered by the First Motive render plane — edit the upstream source, not this file
# fm-tools owns both shared bootstrap pieces: lib.sh (fetched raw, before any
# clone exists) and the fm_tools wheel (the shared TUI banner). Both come from
# one pinned release tag — the single reuse home. Re-pin in the render plane,
# never in a consumer. A host that needs only one of the two still carries both,
# so the pin reads the same everywhere it appears; the disables below declare
# that, rather than splitting the pin into two blocks that can disagree.
# shellcheck disable=SC2034
FM_TOOLS_RAW="https://raw.githubusercontent.com/first-motive/fm-tools/v0.4.1"
# shellcheck disable=SC2034
FM_TOOLS="fm-tools @ git+https://github.com/first-motive/fm-tools@v0.4.1"
# fm-render:end fm-tools-pin

# Resolve the script's own dir (empty when piped via curl|bash).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""

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
install.sh — set up the fm-docker host (macOS only)

Usage: ./install.sh [install|uninstall] [options]

  install      install OrbStack, start the daemon, pull the base image (default)
  uninstall    remove the pulled base image (OrbStack is left in place)

Options:
  --no-pull    install path: set up the runtime only, skip the image pull
  --dry-run    print what would happen, change nothing
  -y, --yes    non-interactive; assume yes (CI mode)
  -h, --help   show this help

Env: FM_SELFTEST=1  load deps + resolve OS, then stop before any host change.
EOF
}

# Fetch + run an action script: from the clone if present, else over the network.
run_helper() {
  local name="$1"
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/scripts/$name" ]; then
    bash "$SCRIPT_DIR/scripts/$name"
  else
    curl -fsSL --proto '=https' --proto-redir '=https' "$RAW_BASE/scripts/$name" | bash
  fi
}

pull_image() {
  if ! fm_has_docker; then
    echo "WARN: docker unavailable — skipping image pull" >&2
    return 0
  fi
  echo "Pulling $IMAGE ..."
  docker pull "$IMAGE" || echo "WARN: pull failed — pull later: docker pull $IMAGE" >&2
}

do_install() {
  local pull="$1" dry="$2"
  echo "fm-docker install (macOS) ..."
  if [ "$dry" = "1" ]; then
    echo "  would install + start OrbStack (install-orbstack.sh, ensure-docker.sh)"
    [ "$pull" -eq 1 ] && echo "  would pull $IMAGE"
    return 0
  fi
  run_helper install-orbstack.sh
  run_helper ensure-docker.sh
  if [ "$pull" -eq 1 ]; then
    pull_image
  fi
  echo "Done."
}

do_uninstall() {
  local dry="$1"
  echo "fm-docker uninstall (macOS) ..."
  if [ "$dry" = "1" ]; then
    echo "  would remove image $IMAGE (if present); OrbStack left in place"
    return 0
  fi
  # Remove only what this installer owns: the pulled image. OrbStack is a shared
  # app a user may rely on elsewhere, so we never uninstall it for them.
  if fm_has_docker && docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker rmi "$IMAGE" && echo "removed $IMAGE"
  else
    echo "image $IMAGE not present; nothing to remove"
  fi
  echo "OrbStack left in place (shared app; remove it yourself if unwanted)."
  echo "Done."
}

main() {
  # Parse before loading lib so --help works offline, with no network fetch.
  local cmd="install" pull=1 dry=0 arg
  for arg in "$@"; do
    case "$arg" in
      install|uninstall) cmd="$arg" ;;
      --no-pull) pull=0 ;;
      --dry-run) dry=1 ;;
      -y|--yes) ;;  # accepted for CI parity; this installer prompts for nothing
      -h|--help) usage; return 0 ;;
      *) echo "ERROR: unknown argument: $arg" >&2; usage; return 2 ;;
    esac
  done

  fm_load_lib

  local os
  os=$(fm_detect_os) || return 1

  # CI self-test hook: deps loaded and OS resolved — stop before any host change.
  # Lets the macOS curl-path test exercise the piped fetch without installing.
  if [ -n "${FM_SELFTEST:-}" ]; then
    echo "selftest ok: lib loaded, os=$os"
    return 0
  fi

  if [ "$os" != "macos" ]; then
    echo "ERROR: install.sh is macOS-only; Linux runs ROS2 Humble natively (see run.sh)." >&2
    return 1
  fi

  case "$cmd" in
    install)   do_install "$pull" "$dry" ;;
    uninstall) do_uninstall "$dry" ;;
  esac
}

main "$@"
