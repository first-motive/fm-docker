#!/usr/bin/env bash
# Fail when any file in this repo names an fm-docker release tag other than the
# pinned one.
#
# The tag appears in prose a curl|bash user copies (README, the usage comments
# in install.sh and run.sh) and in RAW_BASE, which the front doors need before a
# clone exists. None of those can read a file at run time, so each is a literal.
# The pinned value below is rendered from the First Motive render plane — the
# same block the consumer repos render — so this check answers the one question
# that matters: does every literal here agree with the tag consumers install?
#
#   ./scripts/check-tag-refs.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# fm-render:begin fm-docker-pin sha256:532190583135a4c86953f451232f5e222ebd1750e65438ea252618f0c3b44cd2 — rendered by the First Motive render plane — edit the upstream source, not this file
# The container runtime install is delegated to fm-docker, fetched from one
# pinned release tag. Re-pin in the render plane, never in a consumer.
# shellcheck disable=SC2034
FM_DOCKER_RAW="https://raw.githubusercontent.com/first-motive/fm-docker/v0.1.3"
# fm-render:end fm-docker-pin

expected="${FM_DOCKER_RAW##*/}"

# Search tracked files only: a stale tag in an untracked scratch file is not
# something this repo ships. This script names the pattern itself, so exclude it.
offenders="$(
  git grep -InE 'first-motive/fm-docker/v[0-9]+\.[0-9]+\.[0-9]+' -- . \
    | grep -v '^scripts/check-tag-refs\.sh:' \
    | grep -v "fm-docker/$expected" || true
)"

if [ -n "$offenders" ]; then
  echo "error: these name an fm-docker tag other than $expected:" >&2
  echo "${offenders//$'\n'/$'\n  '}" >&2
  echo >&2
  echo "Re-pin in the render plane, let the sync PR land here, then update these to match." >&2
  exit 1
fi

echo "tag refs: every fm-docker tag reference is $expected"
