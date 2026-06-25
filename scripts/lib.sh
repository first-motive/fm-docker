#!/usr/bin/env bash
# Reusable host-detection checks for fm-docker's run.sh and install.sh. Source
# this file — do not execute it. Each function is a pure check: it reports
# through stdout (detect_os) or exit status (has_docker) and mutates no caller
# state, so it is safe to call from any script without side effects.
#
#   source "<repo>/scripts/lib.sh"
#
# Action scripts that change the host (install-orbstack.sh, ensure-docker.sh)
# stay executable and separate; this library carries checks only.

# Echo the host OS as macos|linux; return non-zero on anything else.
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *) echo "ERROR: unsupported OS: $(uname -s)" >&2; return 1 ;;
  esac
}

# True when the Docker CLI is present.
has_docker() {
  command -v docker >/dev/null 2>&1
}
