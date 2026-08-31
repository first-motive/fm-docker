#!/usr/bin/env bash
# Assert the compose base wires the transport the way the consuming repos rely on.
#
#   ./scripts/check-compose-transport.sh
#
# Two shapes, one file. Unset, the base must resolve to something inert: DDS free
# to leave the container and no Cyclone config, which is what a bare
# `docker compose up` on a host with no transport opinion has always got. With the
# zenoh knobs exported, the container must join the host's loopback island —
# ROS_LOCALHOST_ONLY=1 plus a CYCLONEDDS_URI naming the mounted profile.
#
# Worth a check rather than a read: the wiring is three interacting defaults, and
# when it is wrong nothing fails. The bridge routes an empty graph and the topics
# simply never appear (fm-ros2#148).
set -euo pipefail

cd "$(dirname "$0")/.."

fails=0
OUT=""

# Assert a line of the resolved compose file. One function so a check reads as a
# claim about the wiring rather than as a grep.
check() {  # label  pattern
  if grep -qE "$2" <<<"$OUT"; then
    echo "PASS: $1"
  else
    echo "FAIL: $1 (no /$2/ in the resolved file)"
    fails=$((fails + 1))
  fi
}

# `docker compose config` resolves the interpolation and prints the merged file.
# It talks to no daemon, so this runs anywhere the CLI is installed.
resolved() { docker compose -f compose.yaml -f compose.linux.yaml config; }

echo "== defaults (nothing exported) =="
OUT="$(env -u ROS_LOCALHOST_ONLY -u FM_CYCLONEDDS_URI -u FM_CYCLONEDDS_XML \
  bash -c "$(declare -f resolved); resolved")"
check "DDS is not confined when nothing asked for it" 'ROS_LOCALHOST_ONLY: "0"'
check "no Cyclone config by default" 'CYCLONEDDS_URI: ""'
check "the profile mount is inert by default" '/dev/null'

echo "== zenoh profile (the consuming repo exported the host's knobs) =="
OUT="$(ROS_LOCALHOST_ONLY=1 \
  FM_CYCLONEDDS_URI=file:///etc/fm-comms/cyclonedds.xml \
  FM_CYCLONEDDS_XML=/tmp/fm-cyclonedds.xml \
  bash -c "$(declare -f resolved); resolved")"
check "the container joins the host's loopback island" 'ROS_LOCALHOST_ONLY: "1"'
check "Cyclone reads the mounted loopback profile" \
  'CYCLONEDDS_URI: file:///etc/fm-comms/cyclonedds.xml'
check "the host's profile file is mounted in" '/tmp/fm-cyclonedds.xml'

echo
if [[ "$fails" -gt 0 ]]; then
  echo "compose transport: $fails check(s) failed"
  exit 1
fi
echo "compose transport: green"
