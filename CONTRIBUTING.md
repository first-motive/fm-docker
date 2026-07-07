# Contributing

Thanks for contributing. This repo uses an owner-free-on-main model: the owner
pushes to `main` directly, everyone else works on a branch and opens a pull
request for the owner to merge. The owner is set in
[`.github/CODEOWNERS`](.github/CODEOWNERS).

## Workflow

```text
owner:   push main
others:  branch -> PR -> owner merges
```

The merge-to-main rules apply to the owner only. If you are not the owner, you
branch and open a PR — you do not merge.

## Branch Naming

Name branches `prefix/short-phrase`, where the prefix matches the commit prefix
list below and the phrase is a kebab-case summary.

```text
feat/publish-arm64
fix/entrypoint-overlay
docs/inheritance-chain
```

- Lowercase, hyphen-separated.
- No `:` or spaces (invalid in git refs).
- Short — the branch name is a label, not a description.

## Commit Format

Commits are subject-line-only: `prefix: phrase`. Use a lowercase imperative
phrase, no trailing period, no body.

| Prefix     | Use for                                              | Example                          |
| ---------- | --------------------------------------------------- | -------------------------------- |
| `init`     | First commit of a repo (bootstrap only, never after) | `init: scaffold project`         |
| `feat`     | New behavior or content                             | `feat: publish base to ghcr`     |
| `fix`      | Bug fix or content correction                       | `fix: source overlay on launch`  |
| `docs`     | Documentation only                                  | `docs: document inheritance`     |
| `refactor` | Behavior-preserving restructure                     | `refactor: split compose overlay`|
| `chore`    | Tooling, deps, housekeeping                         | `chore: bump build-push action`  |

Pick the narrowest prefix that fits. If a change spans two, split the commit.

## Pull Requests

- One logical change per PR. Split unrelated work.
- Fill the PR template: **what** changed, **why**, and how you **tested** it.
- Keep the branch current with `main` before requesting a merge.

## Repo Conventions

- **Repo** — kebab-case (`fm-docker`), matching the GitHub repo and the
  `first-motive` org.

## Onboarding

New here? The [First Motive org profile](https://github.com/first-motive#get-started)
has the one-curl setup and the `fm update` sync habit.
