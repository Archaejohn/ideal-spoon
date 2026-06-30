# ADR-0002: Repository home & git workflow

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Owner, Architect

## Context
The working directory `RPG_game/` was nested inside a large shared Desktop-level git repository containing many unrelated projects. We need an isolated, releasable repository with a remote we can push to and open PRs against. The authenticated GitHub account `Archaejohn` owns an empty public repo `ideal-spoon` ("A test game").

## Decision
- Initialize `RPG_game/` as its own standalone git repository (`main` default branch), independent of the Desktop repo.
- Use `https://github.com/Archaejohn/ideal-spoon.git` as `origin`.
- Authenticate git pushes via the `gh` CLI credential helper (account `Archaejohn`, scopes `repo`, `workflow`).
- Enforce the branch → PR → independent review → merge workflow by process (see `CONTRIBUTING.md`); the initial scaffold is the one allowed direct-to-`main` commit.

## Rationale
- Isolating the project keeps `main` releasable and history clean, and avoids entangling unrelated Desktop projects.
- `ideal-spoon` is already provisioned, empty, and owned by the authenticated account — zero human action required to start pushing.

## Consequences
- The nested git repo is intentional; the outer Desktop repo will see `RPG_game/` as untracked. We never commit game work into the Desktop repo.
- GitHub server-side branch protection is optional (human-only to enable); the studio enforces equivalent rules by process and CI.
