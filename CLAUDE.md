# CLAUDE.md

Guidance for Claude Code and Codex working in the `fm-docker` repo. See the
[README](README.md) for the overview.

## Purpose

`fm-docker` is the shared container base for First Motive's ROS2 (Humble) stack:
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
- `compose.yaml` is generic: it runs `${FM_IMAGE}` and mounts `${FM_WS}`. The
  `compose.macos.yaml` overlay carries only host-specific bits (platform, ports).
  Containers are macOS-only — Linux runs ROS2 Humble natively, so there is no
  Linux overlay here. Keep per-repo specifics in the consumer repo, not here.

## Publishing

`Dockerfile.base` is built multi-arch (arm64 + amd64) and pushed to
`ghcr.io/first-motive/fm-docker:humble` by `.github/workflows/publish.yml` on
every push to `main` that touches the image.
