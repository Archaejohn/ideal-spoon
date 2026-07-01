# CLAUDE.md — Aetherbound

Guidance for Claude Code working in this repo. **Read `STATUS.md` (live state) and `docs/SESSION_HANDOFF.md` (deep context) first.**

## What this is
**Aetherbound** — a single-player, **fully offline** fantasy/sci-fi **RPG** for **Android + Chromebook**, built by an autonomous AI game studio orchestrated per `ORCHESTRATOR_PROMPT.md`. Engine: **Godot 4.3 / GDScript**. FF-style **ATB** battles, a branching/merging story with multiple endings, original art + music. Audience: a 10-year-old reading at a 6th-grade level (no profanity/gore/mature themes).

- **Repo:** own git repo; remote `origin` = `github.com/Archaejohn/ideal-spoon` (gh account `Archaejohn`). `main` is releasable.
- **Art style (this project's look):** **pixel art, SNES / FF VI / Secret of Mana** register.
- **Hard constraints:** no runtime network/telemetry/ads; deterministic core logic (seeded RNG); data (JSON) separated from code; performance for low-end devices.

## Key commands
```bash
# Run the game (windowed) on Windows:
"tools/bin/Godot_v4.3-stable_win64.exe" --path game
# Run the full GUT test suite (headless):
bash tools/run_tests.sh            # expect: all passing (141 as of P3)
# Fetch/refresh the pinned Godot + GUT toolchain:
bash tools/fetch_godot.sh
```
- After **running the game**, `git checkout -- game/project.godot` (Godot rewrites it on launch, stripping the `[rendering]` gl_compatibility section — a real regression).

## Repo map
| Path | What |
|---|---|
| `game/` | Godot 4.3 project. `src/` (core, story, battle, save, data, ui, overworld, leveling), `data/` (JSON content), `tests/` (GUT), `addons/gut/`. |
| `docs/story/` | Story bible (locked & approved). `03_MAIN_STORY.md` beat ledger + `04_BRANCHES_ENDINGS.md` resolver are the engine contract. |
| `docs/architecture/` | `ARCHITECTURE.md`, phase reviews. |
| `docs/decisions/` | ADRs (0001–0009). Add ADRs for nontrivial decisions. |
| `docs/art/` | Style guide + critiques (NOTE: current guide is painterly; pixel guide pending). |
| `tools/art/` | Local art-gen tooling (see Art pipeline). |
| `tools/bin/` | git-ignored: Godot, GUT dl, `resvg.exe`, `vtracer.exe`, `ffmpeg.exe`. |
| `DEFINITION_OF_DONE.md`, `CONTRIBUTING.md`, `STATUS.md`, `DECISIONS.md`, `NEEDS_HUMAN.md` | Governance. |

## Workflow (mandatory)
- Branch → implement **with GUT tests** → PR (`gh pr create`) → **independent review** (reviewer ≠ author) → merge (`gh pr merge --squash`). `main` stays green/releasable. Conventional Commits.
- Reviews have repeatedly caught real bugs — keep the discipline. Logic is deterministic and headless-testable; UI/coordinators may use the scene tree/autoloads (guarded by `test_module_boundaries` / `test_no_nondeterminism`).
- Commit trailers:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01PNWRn3sZSv7KPZzPGkyReL
  ```

## Engine architecture (see ADR-0003..0009)
Autoloads (dependency order): `Log, RngService, EventBus, ContentDB, SettingsService, GameState, SaveManager, SceneRouter, GameCoordinator, BattleController`. Story/battle/save logic is pure `RefCounted`, injected deps, no scene-tree coupling. `EndingResolver` is line-for-line with story `04` and pinned by a golden test. Saves are automatic + atomic (temp→validate→backup→rename) with pre-battle checkpoints (RNG cursors included).

## Art pipeline (pixel; fully local, offline)
Runtime never touches this — it's a build-time asset tool.
1. **ComfyUI** (owner's Desktop app) at `http://127.0.0.1:8000`. Model: `flux-2-klein-base-4b` + `qwen_3_4b` + `flux2-vae` (in `C:\Users\cpjel\ComfyUI-Shared\models`). ~1.5–2 min/gen on RTX 4060 (8GB).
2. `tools/art/comfy_gen.py` — text→image (base sprites). `comfy_edit.py` — 1-reference edit (ReferenceLatent; preserves character, changes pose/expression). `comfy_edit_multi.py --src a b c` — multi-reference edit. Base graph: `tools/art/flux2_klein_workflow.json`.
3. **Recipe:** generate base → **edit** for each frame/pose → **review every candidate**, place opportunistically into whichever sequence slot fits (cap 10/slot, stop early) → **lock all frames to one master palette + feet-align** (PIL) → assemble (ffmpeg gif/mp4). Low SNES frame counts.
4. `resvg`/`vtracer` for UI/icons only; `rembg` (pip) for background cutout.
- **Verify rendered artifacts directly** (extract frames from the final file; check timestamps) — do not trust "done" claims or separately-exported stills.

## Current state
Phases 0–3 complete & merged (playable slice, 141 tests). On `feat/phase4-art-pipeline`; the pixel art pipeline is proven (full N/S/E/W walk) but **not yet formally locked** (pixel style guide + palette + ADR pending owner go-ahead), after which Phase 4 full production begins. The one human gate (story) was passed; run autonomously otherwise, surfacing human-only blockers in `NEEDS_HUMAN.md`.

## Orchestration gotchas
- Parallel file-writing subagents → use `isolation:"worktree"`. Don't switch branches while a subagent reads the tree.
- Phone/CDN viewers can cache old media — re-render to new filenames when verifying fixes.
