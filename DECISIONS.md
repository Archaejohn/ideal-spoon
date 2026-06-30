# Decision Log

Running index of Architecture Decision Records (ADRs). Newest at top. Full records live in `docs/decisions/`.

| ADR | Title | Status | Date |
|---|---|---|---|
| [0001](docs/decisions/ADR-0001-tech-stack.md) | Engine, language, testing, and toolchain | Accepted | 2026-06-30 |
| [0002](docs/decisions/ADR-0002-repo-and-remote.md) | Repository home & git workflow | Accepted | 2026-06-30 |

## Standing decisions (set by charter, not up for debate)
- **Engine:** Godot 4.x (latest stable), GDScript.
- **Unit testing:** GUT, committed as an addon; tests mandatory and run in CI.
- **Battle:** Active-Time-Battle (FF-like).
- **Targets:** Android phone + Chromebook; single-player; fully offline; no ads/telemetry/network.
- **Audience:** 10-year-old, 6th-grade reading level; epic fantasy/sci-fi; no profanity/graphic violence/mature themes.
- **Narrative scope:** original story with the weight of FF III/VI — branching diverge/merge paths, side quests, multiple endings.
- **No external paid APIs; no external image APIs.** Art via layered SVG craft + critic loop.
