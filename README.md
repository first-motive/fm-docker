# fm-docker

Shared container base for First Motive's ROS2 (Humble) robot stack.

It holds the base image, the entrypoint, and the host compose overlays. As the
root of the image inheritance chain, each downstream image is `FROM` its parent
— dependencies layer down instead of forming one monolith. Each layer is a
separate `first-motive` repo, assembled by the `fm-ros2` orchestrator.

## Image Inheritance

```
fm-docker base       ros:humble + tooling + viz + xacro/rsp        (view any robot)
   └ fm-robot   FROM base    + ros2-control                        (description + control + sensors)
        ├ fm-sim     FROM robot  + mujoco/gz/xvfb
        └ fm-teleop  FROM robot  + moveit/servo
   └ fm-app     FROM robot  + sim & teleop apt deps + textual      (full-stack launcher)
```

The base image is published to GHCR multi-arch (arm64 + amd64), so one tag runs
on Apple silicon (OrbStack) and Linux:

```
ghcr.io/first-motive/fm-docker:humble
```

## Install

This repo is self-sufficient — it carries the host tooling to set up a runtime
and drop into the base image, so you can verify the layer without a consumer
repo. `install.sh` is idempotent and safe to re-run.

```bash
# Set up the host runtime + pull the base image (no clone needed).
curl -fsSL https://raw.githubusercontent.com/first-motive/fm-docker/main/install.sh | bash

# Or from a clone:
./install.sh            # auto-detects macOS / Linux
./install.sh --no-pull  # runtime setup only, skip the image pull
```

On macOS, `install.sh` installs OrbStack and starts the daemon. On Linux, it
reports the Docker / NVIDIA / X11 tooling it finds and points at the fix for
anything missing.

## Usage

```bash
# Drop into a ROS2 Humble shell. macOS always uses the container; Linux runs
# native ROS2 when /opt/ros/humble is present, else falls back to the container.
./run.sh

./run.sh --container    # force the container even when native ROS2 is present
./run.sh --local        # force native bare-metal (Linux only)
./run.sh --pull         # container path: refresh :humble first
./run.sh --build        # container path: build Dockerfile.base locally
```

The container reuses the local `:humble` image and pulls only when it is
missing. The base rarely changes, so re-entry stays fast and works offline.

## Contents

| File                  | Role                                                          |
| --------------------- | ------------------------------------------------------------- |
| `Dockerfile.base`     | Minimal ROS2 Humble base: build tooling, viz, xacro, rsp/jsp. |
| `ros_entrypoint.sh`   | Sources the ROS distro, then the workspace overlay if built.  |
| `compose.yaml`        | Shared compose base. Consumers set `FM_IMAGE` + `FM_WS`.      |
| `compose.macos.yaml`  | macOS (Apple silicon, OrbStack) overlay — sim only, no GPU.   |
| `compose.linux.yaml`  | Linux overlay — device passthrough, X11, host net (no GPU).    |
| `install.sh`          | Host setup: container runtime + base image pull. Curl-able.   |
| `run.sh`              | Pull (or `--build`) the base, drop into an interactive shell. |
| `scripts/lib.sh`      | Sourced host checks (OS, ROS2, GPU, docker, X11) — no actions. |
| `scripts/`            | macOS runtime actions: install OrbStack, ensure the daemon.   |
| `COLCON_IGNORE`       | Marks the repo so colcon never builds it as a package.        |

## Use From a Consumer Repo

Each package repo imports these overlays through its `*.repos` manifest and runs
the stack with its own `run.sh`. The base compose runs a published image; the
overlay adds the host-specific bits:

```bash
# macOS
FM_IMAGE=ghcr.io/first-motive/fm-robot:humble \
  docker compose -f compose.yaml -f compose.macos.yaml up

# Linux
FM_IMAGE=ghcr.io/first-motive/fm-robot:humble \
  docker compose -f compose.yaml -f compose.linux.yaml up
```

`FM_IMAGE` (required) selects the layered image to run. `FM_WS` is the host
workspace mounted at `/ws`, defaulting to the directory you run compose from.

## CI

- `ci.yml` — every PR and push to `main`: shellcheck on host scripts, an amd64
  build of `Dockerfile.base` (no push), and a smoke test for the ROS runtime and
  description/viz packages.
- `publish.yml` — push to `main` that touches the image: multi-arch (arm64 +
  amd64) build, push `:humble` to GHCR.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
