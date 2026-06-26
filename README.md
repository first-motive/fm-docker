# fm-docker

Shared container base for First Motive's ROS2 (Humble) robot stack.

It holds the base image, the entrypoint, and the host compose overlays. As the
root of the image inheritance chain, each downstream image is `FROM` its parent
— dependencies layer down instead of forming one monolith. Each layer is a
separate `first-motive` repo, assembled by the `fm-ros2` orchestrator.

## Quick Start

This repo is self-sufficient — it carries the host tooling to drop into the base
image, so you can verify the layer without a consumer repo. One command gets you
a shell, no clone needed:

```bash
curl -fsSL https://raw.githubusercontent.com/first-motive/fm-docker/v0.1.0/run.sh | bash
```

`run.sh` dispatches on the host OS:

- **macOS** → container. OrbStack is installed and started automatically when
  missing; the `:humble` image pulls on first run, then is reused offline.
- **Linux** → native ROS2 at `/opt/ros/humble`. There is no container path on
  Linux; without a native Humble install, `run.sh` exits with guidance.

Piped via curl, `run.sh` caches `lib.sh` and the compose files under
`~/.cache/fm-docker` and reuses them offline. From a clone, the same dispatch
applies, plus the macOS build/refresh flags:

```bash
./run.sh            # OS-detected: macOS container, Linux native
./run.sh --pull     # macOS: refresh the :humble image first
./run.sh --build    # macOS: build Dockerfile.base locally (clone only)
```

To set up the macOS runtime and pull the image ahead of time, use `install.sh`
(macOS-only, idempotent, also curl-able):

```bash
curl -fsSL https://raw.githubusercontent.com/first-motive/fm-docker/v0.1.0/install.sh | bash
./install.sh --no-pull  # from a clone: runtime only, skip the image pull
```

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

## Contents

| File                  | Role                                                          |
| --------------------- | ------------------------------------------------------------- |
| `Dockerfile.base`     | Minimal ROS2 Humble base: build tooling, viz, xacro, rsp/jsp. |
| `ros_entrypoint.sh`   | Sources the ROS distro, then the workspace overlay if built.  |
| `compose.yaml`        | Shared compose base. Consumers set `FM_IMAGE` + `FM_WS`.      |
| `compose.macos.yaml`  | macOS (Apple silicon, OrbStack) overlay — dev/build/sim/dataset; no GPU. |
| `install.sh`          | macOS host setup: install OrbStack + pull base image. Curl-able. |
| `run.sh`              | Drop into a shell — macOS container or Linux native. Curl-able. |
| `scripts/lib.sh`      | Sourced host checks (OS, docker) — no actions.                |
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
