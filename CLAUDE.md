# CLAUDE.md

Guidance for Claude Code and Codex working in the `fm-docker` repo. See the
[README](README.md) for the overview.

## Purpose

`fm-docker` is the shared container base for First Motive's ROS2 stack:
the base image, the entrypoint, and the host compose overlays. It is the root of
the image inheritance chain — every package repo's image is `FROM` a layer that
traces back here. Part of First Motive's ROS2 stack, consumed by
[`fm-ros2`](https://github.com/first-motive/fm-ros2) and the package repos.

## Conventions

- Commit and branch rules live in `CONTRIBUTING.md`. Follow them.
- Commits are subject-line-only: `prefix: phrase`. No body.
- Repo is kebab-case.

## Layers

- `Dockerfile.base` is the minimal base only: ROS2 Humble, build tooling, viz,
  xacro, robot/joint state publishers. Control, sim, MoveIt, and the TUI live in
  downstream repos' images, each `FROM` its parent. Do not add a downstream
  layer's deps here — that would re-monolith the base.
- `compose.yaml` is generic: it runs `${FM_IMAGE}` and mounts `${FM_WS}`. An
  overlay carries only host-specific bits and never per-repo specifics, which
  belong in the consumer repo:
  - `compose.macos.yaml` — platform and published ports. No GPU, no hardware.
  - `compose.linux.yaml` — GPU reservation, host networking and IPC, `/dev`
    passthrough, X11.
- `run.sh` still takes the native path on Linux. The Linux overlay is for a
  consumer repo's own `run.sh`, which is where the GPU container path lives.

## Publishing

`Dockerfile.base` is built multi-arch (arm64 + amd64) and pushed to
`ghcr.io/first-motive/fm-docker:humble` by `.github/workflows/publish.yml` on
every push to `main` that touches the image. A published release additionally
pushes `:vX.Y.Z`, taken from the release's git tag.

`:humble` moves; a version tag and a digest do not. Downstream `Dockerfile`s
build `FROM :humble`, but anything that provisions a host holds the digest —
`compose.yaml` and `install.sh` both pin it, and they move together. Never
change one of those two lines alone, and never point either back at `:humble`.
The release and bump flow is in the [README](README.md#releasing).
