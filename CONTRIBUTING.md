# Contributing

Thanks for contributing.

## Workflow

<!-- fm-render:begin contributing-workflow sha256:0b338cf09d4d1b502e22336f5422ce7326b73d01761b04fd581159748aea6bb4 — rendered by the First Motive render plane — edit the upstream source, not this file -->
Work reaches `main` by merging a pull request with green checks — never by
pushing to it. This holds for everyone, the owner included. The rendered
`.fm/hooks/pre-push` refuses a direct push, a tripwire workflow files an issue
against one that arrives from an unguarded clone, and ADR 0001 in
`first-motive/.github` records the decision.

```text
everyone:  branch -> PR -> green checks -> merge
```

`FM_ALLOW_MAIN_PUSH=1` is the loud escape for an emergency; a push that takes
it is still reported by the tripwire. The repo owner is set in
[`.github/CODEOWNERS`](.github/CODEOWNERS).

Coding agents follow the same path and merge their own PRs once checks are
green. `gh pr merge --admin` is allowed when a required review is the only
blocker; it is never used to get past a failing check.
<!-- fm-render:end contributing-workflow -->

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
