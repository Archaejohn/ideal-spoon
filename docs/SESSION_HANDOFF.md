# Session Handoff — Aetherbound

_Last updated: 2026-07-01. Read this + `STATUS.md` to resume. The repo is the source of truth._

## TL;DR
- **Phases 0–3 are DONE and merged to `main`** (141 GUT tests green; a playable vertical slice runs). See "Merged work."
- The rest of the session was **art-pipeline R&D**, which converged on a **proven pixel-art pipeline** (Flux.2 Klein generate + edit + per-frame review + palette-lock). A full **N/S/E/W walk cycle** was produced as proof.
- **Open decision (not yet locked):** formally adopt the pixel pipeline — write the pixel `STYLE_GUIDE.md` + master palette + an art ADR, then resume Phase 4 production. The owner ran the art work as trials and has **not** yet said "lock it."

## Repo / git state
- Default branch `main` is releasable: Phase 0–3 merged via PRs #1–#7. `bash tools/run_tests.sh` → **141 passing**.
- **Current branch: `feat/phase4-art-pipeline`** (checked out). Contains the art tooling (1 commit) + lots of uncommitted art R&D now being committed with this handoff. No open PRs.
- Heavy art outputs and throwaway animation-prototype projects are **git-ignored** (`art/_render/`, `art/refs/`, `art/pixel_anim/candidates/`, `tools/art/{mesh_deform,skeletal_demo,skeletal_walk}/`, `tools/bin/`). The reusable master pixel bases (`art/pixel_anim/master_base_*.png`) and tooling scripts ARE committed.

## Merged work (main) — Phases 0–3
- **P0 Bootstrap:** standalone repo → `github.com/Archaejohn/ideal-spoon`; governance docs; Godot 4.3 project (`game/`); GUT vendored (`game/addons/gut`); CI.
- **P1 Story (APPROVED — the single human gate):** full bible in `docs/story/` (world, cast incl. mascot **Piggy**, 4-act beat ledger `A1-01..A4-07`, branches BR1–BR4, 4 endings + deterministic resolver, side quests, key-scene scripts, heart pass, light/triumph pass).
- **P2 Architecture:** `docs/architecture/ARCHITECTURE.md` + ADR-0003..0009 (story-graph/flag engine, ATB battle, **save/persistence**, **ending-replay**, content schema, scene flow, determinism/testing).
- **P3 Vertical slice (playable):** foundation (RNG, FlagStore/FlagView/FlagOps, EndingResolver + golden test), core systems (StoryDirector, ATB BattleEngine + EnemyBrain + LevelSystem, crash-safe SaveManager), integration shell (SceneRouter, GameCoordinator, autoloads, Title/New/Continue/autosave), playable ATB battle with pre-battle checkpoint + lose→restore, narrative slice (Meadowmoor→Hollowgate→wreck→Sleepless Crane→1 branch), dialogue UI. Every PR passed independent review.

### Owner functional requirements (baked into DEFINITION_OF_DONE #13/#14)
1. Automatic, crash-safe saving + battle checkpoints (survive shutoff/lock/app-kill; lose-a-battle resumes pre-battle).
2. Replayable endings from their story-divergence point (post-game "Crossroads").
3. **Design intent (from this session):** classic FF-style **progressively-opening overworld map** (a "Skyway Map" of skylands you pilot between; islands unlock via story flags; enter towns/dungeons). Build in Phase 4.

## The art pipeline (the big outcome of this session)
**Decision: PIXEL ART, SNES / FF VI / Secret of Mana register** (owner's call). This resolved a long reliability struggle. Journey:
- Painterly raster looked great but **vectorizing it failed** (traced 5/10, hand-authored SVG 3/10) — style doesn't survive tracing.
- **Auto-rigging a flat image is fragile** (rigid-cutout seams; mesh-deform warp + "bites"/coverage bugs). Not reliable at scale.
- **Character consistency** is the core blocker: text-to-image gives a *different* character per generation.
- **Flux.2 image EDIT (ReferenceLatent) solves consistency** — it preserves the source character and changes only what's instructed (proven: expression + wave stayed on-model). Multi-reference edit also available.
- **Pixel art + edit is the reliable, automated, local pipeline.** Proven end-to-end with a full N/S/E/W walk.

### The proven recipe
1. **Base sprite:** Flux.2 Klein text-gen, pixel-styled, reviewed (`tools/art/comfy_gen.py`).
2. **Directional bases:** seed-locked text-gen per facing (front/side/back stayed consistent), or edit-turn (owner has had success turning L/R; multi-ref improves it).
3. **Animation frames:** Flux.2 **edit** (`tools/art/comfy_edit.py`) — per-frame; generate candidates, **review each**, place each candidate into whichever sequence slot it best fits (opportunistic, not slot-locked), only re-edit unfilled slots, **cap 10 attempts/slot, stop early when adequate**.
4. **Lock a master palette + feet-align** every frame (kills color flicker + positional jitter). Low SNES frame counts (3–5).
5. **Multi-reference** edit (`tools/art/comfy_edit_multi.py`, `--src a.png b.png c.png`) for extra consistency (front+side+back, or char+pose ref).

### Local art toolchain (all offline; game never touches it at runtime)
- **ComfyUI (owner's, Desktop app)** running at `http://127.0.0.1:8000`. Model stack: `flux-2-klein-base-4b.safetensors` + `qwen_3_4b` text encoder + `flux2-vae` (models in `C:\Users\cpjel\ComfyUI-Shared\models`). ~1.5–2 min/gen on an RTX 4060 (8GB). Image-edit template on disk: `image_flux2_klein_image_edit_4b_base.json`.
- Base API graph pulled from ComfyUI `/history` → `tools/art/flux2_klein_workflow.json` (text-gen). Edit tools graft `LoadImage→VAEEncode→ReferenceLatent→CFGGuider.positive` onto it.
- `tools/bin/` (git-ignored): `resvg.exe` (SVG→PNG), `vtracer.exe` (raster→SVG, UI/icons only), `ffmpeg.exe` (video/gif). `rembg` installed via pip (bg removal); PIL/numpy present.
- Scripts: `comfy_gen.py` (t2i), `comfy_edit.py` (1-ref edit), `comfy_edit_multi.py` (N-ref edit), `_walk_batch*.sh` (candidate batches).
- Deliverables produced: `art/pixel_anim/master_base_{south,north,east}.png` (reusable), full N/S/E/W 3-frame walk (`art/_render/walk_4dir.gif`, git-ignored).

### Known residuals / next art steps
- North base puts the pendant on the back (trivial edit fix). Front/back leg motion is slightly "marionette" (side views are best). Add attack/cast/hurt frames per direction; consider a Flux pixel-art LoRA later for stricter pixels.
- Superseded prototypes (painterly SVG, skeletal/mesh rigs) are kept locally but git-ignored; `docs/art/STYLE_GUIDE.md` is the *painterly* guide and must be **rewritten for pixel art** if the pipeline is locked.

## Resume plan
1. **If locking the art pipeline:** write pixel `docs/art/STYLE_GUIDE.md` + `docs/art/PALETTE.*` (master palette), an art ADR (pixel raster; Flux.2 gen+edit+review+palette-lock; no rigging; ComfyUI-local), retire the painterly guide, merge `feat/phase4-art-pipeline`.
2. **Phase 4 production loop:** author all story content into `game/data/` (beats/branches/dialogue/quests/items/enemies/encounters), build the **Skyway overworld map** + full menus + ending-replay Crossroads, and produce the cast/enemy/tile/portrait pixel art via the recipe above (per-asset critic ≥8/10 gate). Then **Phase 5** hardening + Android/Chromebook builds.

## Gotchas / lessons (important)
- **Verify the actual artifact, not agent claims or exported stills.** Agents twice reported renders that didn't happen / stills that didn't match the video. Always extract frames from the final MP4/GIF and check file timestamps (output must be newer than inputs).
- **Parallel file-writing subagents need `isolation:"worktree"`.** Running 3 in one checkout stacked commits onto one branch (recovered, but risky).
- **Never switch git branches while a subagent is reading the working tree.**
- **Launching the Godot game rewrites `game/project.godot`** (strips comments + the `[rendering]` gl_compatibility section). After running the game, `git checkout -- game/project.godot`.
- **Phone/CDN viewer can cache** an old GIF/MP4 — re-render to a *new filename* when in doubt.
- **Flux.2 edit-turn works** for L/R rotation (owner-confirmed); big action-pose edits are the weak case. Consistency across poses = use **edit**, not fresh gen.
