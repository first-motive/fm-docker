# fm-docker

Shared container base for First Motive's ROS2 (Humble) robot stack. This repo
holds the base image, the entrypoint, and the host compose overlays that every
First Motive package repo builds on. It is the root of the image inheritance
chain — each downstream repo's image is `FROM` its parent, so dependencies point
down through clear layers instead of one monolithic build.

Each layer below is a separate package repo under the `first-motive` GitHub org,
assembled by the `fm-ros2` orchestrator.

## Image Inheritance

```
fm-docker base       ros:humble + tooling + viz + xacro/rsp        (view any robot)
   └ fm-robot   FROM base    + ros2-control                        (description + control + sensors)
        ├ fm-sim     FROM robot  + mujoco/gz/xvfb
        └ fm-teleop  FROM robot  + moveit/servo
   └ fm-app     FROM robot  + sim & teleop apt deps + textual      (full-stack launcher)
```

The base image is published to GHCR multi-arch (arm64 + amd64), so the same tag
runs on Apple silicon (OrbStack) and on Linux:

```
ghcr.io/first-motive/fm-docker:humble
```

## Contents

| File                  | Role                                                          |
| --------------------- | ------------------------------------------------------------- |
| `Dockerfile.base`     | Minimal ROS2 Humble base: build tooling, viz, xacro, rsp/jsp. |
| `ros_entrypoint.sh`   | Sources the ROS distro, then the workspace overlay if built.  |
| `compose.yaml`        | Shared compose base. Consumers set `FM_IMAGE` + `FM_WS`.      |
| `compose.macos.yaml`  | macOS (Apple silicon, OrbStack) overlay — sim only, no GPU.   |
| `compose.linux.yaml`  | Linux overlay — GPU, device passthrough, X11.                 |

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

`FM_IMAGE` selects the layered image to run; `FM_WS` (default: current dir) is the
host workspace mounted at `/ws`. Only `FM_IMAGE` is required — `FM_WS` falls back
to the directory you run compose from.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
