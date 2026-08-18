# fm-docker

Shared container base for First Motive's ROS2 robot stack.

It holds the base image, the entrypoint, and the host compose overlays. As the
root of the image inheritance chain, each downstream image is `FROM` its parent
— dependencies layer down instead of forming one monolith. Each layer is a
separate `first-motive` repo, assembled by the `fm-ros2` orchestrator.

## Quick Start

This repo is self-sufficient — it carries the host tooling to drop into the base
image, so you can verify the layer without a consumer repo. One command gets you
a shell, no clone needed:

```bash
curl -fsSL https://raw.githubusercontent.com/first-motive/fm-docker/v0.1.3/run.sh | bash
```

`run.sh` dispatches on the host OS:

- **macOS** → container. OrbStack is installed and started automatically when
  missing; the pinned base image pulls on first run, then is reused offline.
- **Linux** → native ROS2 at `/opt/ros/humble`. `run.sh` takes the native path
  and exits with guidance when Humble is absent. The container path exists on
  Linux too, through `compose.linux.yaml`, but it is driven by a consumer repo's
  own `run.sh` rather than by this one.

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
curl -fsSL https://raw.githubusercontent.com/first-motive/fm-docker/v0.1.3/install.sh | bash
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
ghcr.io/first-motive/fm-docker:humble                  # moves with main
ghcr.io/first-motive/fm-docker:v0.1.1                  # a release, never moves
ghcr.io/first-motive/fm-docker@sha256:<digest>         # one exact image
```

`:humble` is the tag a downstream `Dockerfile` builds `FROM` — a layer wants the
newest base it can rebuild against. Anything that provisions a host uses the
digest or a version tag instead, which is why `compose.yaml` pins the digest.
Left on `:humble`, a rebuild would change what every provisioned host runs the
next time it pulled, retroactively and with no commit to point at.

## Releasing

A release publishes the image and is the only thing that mints a version tag:

1. Tag the commit and publish the GitHub release: `vX.Y.Z`, matching the tag the
   `run.sh` and `install.sh` curl lines already carry.
2. `publish.yml` builds multi-arch and pushes `:humble` plus `:vX.Y.Z`. The job
   summary prints the digest of that build.
3. Paste the digest into the `image:` line of `compose.yaml` and the `IMAGE`
   line of `install.sh`, which move together, and commit.

Step 3 is deliberately manual. The digest is what provisioned hosts follow, so
moving it is a decision someone makes and reviews, not a side effect of a build.

The version tag itself has one tracked home: the `fm-docker-pin` block in the
First Motive render plane, which every consumer repo renders into its own
installer. Re-pin it there and let the sync PR land here. Inside this repo the
tag stays a literal wherever a curl|bash reader has no clone to read it from —
the README lines above, the usage comments, and `RAW_BASE`. CI's `tag refs` job
runs `scripts/check-tag-refs.sh`, which fails when any of those disagrees with
the rendered pin.

## Contents

| File                  | Role                                                          |
| --------------------- | ------------------------------------------------------------- |
| `Dockerfile.base`     | Minimal ROS2 Humble base: build tooling, viz, xacro, rsp/jsp. |
| `ros_entrypoint.sh`   | Sources the ROS distro, then the workspace overlay if built.  |
| `scripts/check-tag-refs.sh` | Fails CI when a tag literal disagrees with the rendered pin. |
| `compose.yaml`        | Shared compose base. Consumers set `FM_IMAGE` + `FM_WS`.      |
| `compose.macos.yaml`  | macOS (Apple silicon, OrbStack) overlay — dev/build/sim/dataset; no GPU. |
| `compose.linux.yaml`  | Linux overlay — NVIDIA GPU, host networking and IPC, `/dev` passthrough, X11. |
| `install.sh`          | macOS host setup: install OrbStack + pull base image. Curl-able. |
| `run.sh`              | Drop into a shell — macOS container or Linux native. Curl-able. |
| `scripts/`            | macOS runtime actions: install OrbStack, ensure the daemon.   |
| `COLCON_IGNORE`       | Marks the repo so colcon never builds it as a package.        |

## Use From a Consumer Repo

Each package repo imports these overlays through its `*.repos` manifest and runs
the stack with its own `run.sh`. The base compose runs a published image; the
overlay adds the host-specific bits:

```bash
# macOS
FM_IMAGE=ghcr.io/first-motive/fm-robot:v0.1.1 \
  docker compose -f compose.yaml -f compose.macos.yaml up

# Linux, with a GPU and hardware attached
FM_IMAGE=ghcr.io/first-motive/fm-robot:v0.1.1 \
  docker compose -f compose.yaml -f compose.linux.yaml up
```

The Linux overlay reserves the GPU through the NVIDIA container toolkit, so the
host needs it installed — `fm-setup`'s `nvidia-container` step does that. Verify
with `docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi`
before blaming the stack.

`FM_IMAGE` (required) selects the layered image to run — give it a version tag
or a digest, never `:humble`. `FM_WS` is the host workspace mounted at `/ws`,
defaulting to the directory you run compose from.

## CI

- `ci.yml` — every PR and push to `main`: shellcheck on host scripts, an amd64
  build of `Dockerfile.base` (no push), and a smoke test for the ROS runtime and
  description/viz packages.
- `publish.yml` — push to `main` that touches the image, or a published release:
  multi-arch (arm64 + amd64) build, push `:humble` to GHCR, plus `:vX.Y.Z` when
  the run came from a release tag.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
