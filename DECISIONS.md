# Decision Log

Running index of Architecture Decision Records (ADRs). Newest at top. Full records live in `docs/decisions/`. The whole-game system overview these ADRs realize is in [`docs/architecture/ARCHITECTURE.md`](docs/architecture/ARCHITECTURE.md).

| ADR | Title | Status | Date |
|---|---|---|---|
| [0009](docs/decisions/ADR-0009-determinism-rng-testing.md) | Determinism, RNG & testing strategy | Accepted | 2026-06-30 |
| [0008](docs/decisions/ADR-0008-scene-flow-state-machine.md) | Scene flow & app state machine | Accepted | 2026-06-30 |
| [0007](docs/decisions/ADR-0007-content-data-schema-pipeline.md) | Content data schema & pipeline | Accepted | 2026-06-30 |
| [0006](docs/decisions/ADR-0006-ending-replay-crossroads.md) | Ending-replay / Crossroads selector | Accepted | 2026-06-30 |
| [0005](docs/decisions/ADR-0005-save-persistence.md) | Save & persistence (automatic, crash-safe) | Accepted | 2026-06-30 |
| [0004](docs/decisions/ADR-0004-atb-battle-engine.md) | ATB battle engine | Accepted | 2026-06-30 |
| [0003](docs/decisions/ADR-0003-story-graph-flag-engine.md) | Story-graph & flag/quest-state engine | Accepted | 2026-06-30 |
| [0002](docs/decisions/ADR-0002-repo-and-remote.md) | Repository home & git workflow | Accepted | 2026-06-30 |
| [0001](docs/decisions/ADR-0001-tech-stack.md) | Engine, language, testing, and toolchain | Accepted | 2026-06-30 |

## Standing decisions (set by charter, not up for debate)
- **Engine:** Godot 4.x (latest stable), GDScript.
- **Unit testing:** GUT, committed as an addon; tests mandatory and run in CI.
- **Battle:** Active-Time-Battle (FF-like).
- **Targets:** Android phone + Chromebook; single-player; fully offline; no ads/telemetry/network.
- **Audience:** 10-year-old, 6th-grade reading level; epic fantasy/sci-fi; no profanity/graphic violence/mature themes.
- **Narrative scope:** original story with the weight of FF III/VI — branching diverge/merge paths, side quests, multiple endings.
- **No external paid APIs; no external image APIs.** Art via layered SVG craft + critic loop.
