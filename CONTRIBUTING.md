# Contributing & Workflow (mandatory)

This is an engineered project, not a vibe-coded one. Every change follows this process.

## Branching
- `main` is always releasable. **No direct commits to `main`** except the initial scaffold.
- All work happens on a focused feature branch:
  - `feat/…` features and systems
  - `fix/…` bug fixes
  - `art/…` art assets
  - `music/…` audio
  - `story/…` writing/content
  - `test/…` tests/tooling
- Conventional Commits messages (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `art:`, `music:`…). Small, focused PRs.

## PR lifecycle (every change)
1. Branch from latest `main`.
2. Implement **with tests** (logic changes require GUT tests).
3. Run the full test suite locally; record the result in the PR body.
4. Open a PR (`gh pr create`). Link the relevant ADR/issue.
5. **Independent review** — the reviewer is NOT the author. Reviewer checks correctness, design, tests, and standards.
6. Resolve all review comments.
7. Merge only when: tests pass (CI green), reviewer approved, no unresolved comments (`gh pr merge --squash`).

## Roles & separation of duties
- An engineer **never** reviews or approves their own code.
- Art is critiqued by an **independent** Art Critic (not the artist) and must clear the Art Quality Loop in `docs/art/STYLE_GUIDE.md`.
- The **Architect** owns the "advance the phase?" decision, gated on the Definition of Done.

## Decisions
- Every nontrivial decision is recorded as an ADR in `docs/decisions/ADR-XXXX-*.md` and indexed in `DECISIONS.md`.

## Engineering standards
- Clear module boundaries; documented public interfaces; no god-objects.
- Deterministic core logic (seeded RNG) so it is unit-testable.
- Data (story graph, items, enemies, dialogue) separated from code as JSON/resources.
- No runtime network access, telemetry, or ads. Performance budget suits low-end Android + Chromebook.

## CI
- GitHub Actions runs the GUT suite on every PR (`.github/workflows/ci.yml`). A PR cannot merge with failing tests. If Actions minutes are unavailable, the full suite is run locally (headless Godot) and the result is pasted into the PR before merge.
