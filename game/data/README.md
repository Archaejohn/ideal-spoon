# `game/data/` — Content (the writers' & designers' home)

All **content** lives here as plain JSON, separated from engine **code** in `game/src/`. This is the
contract between writers/designers and engineers, governed by **ADR-0007** (schemas & pipeline),
**ADR-0003** (story graph, flags, the ending resolver), and **ADR-0004** (battle data shapes). Edit
content here **without touching `.gd` files**.

## Folders

| Folder | What lives here | Schema / ADR |
|---|---|---|
| `beats/` | One record per story beat (`A1-01 … A4-07`, incl. `A1-06a/b`, `A2-10b`, `A3-02b/c`, `A3-03b/c`, `A3-04b`, `A3-13b`). | ADR-0007 *Beat* |
| `branches/` | `BR1–BR4` definitions (options, per-option effects, merge beat). | ADR-0007 *Branch* |
| `flags/` | `flags.json` registry (gating vs. non-gating) + `unity_sources.json` (the eight `+1` sources). | ADR-0003, ADR-0007 |
| `items/` | Consumables, weapons, armor, accessories, key items. | ADR-0007 *Item* |
| `enemies/` | Enemy stat blocks, weaknesses, abilities, loot. | ADR-0004, ADR-0007 *Enemy* |
| `abilities/` | Party + enemy abilities (cost, targeting, effects). | ADR-0004, ADR-0007 *Ability* |
| `statuses/` | Status effects (duration, stacking, ATB modifiers). | ADR-0004, ADR-0007 *Status* |
| `party/` | Playable members' base stats, growth, learned abilities. | ADR-0007 *Party member* |
| `dialogue/` | Dialogue line sets keyed by a beat's `dialogue_set`. | ADR-0007 *Dialogue* |
| `quests/` | `CQ-*/SQ-*/MA-*` quest definitions. | ADR-0007 *Quest* |
| `endings/` | The four endings (`A/B/C/D`) + `requires` (for replay reconstruction). | ADR-0006, ADR-0007 *Ending* |
| `level_curves/` | XP→level tables and stat growth curves. | ADR-0004 |
| `schema/` | Human-readable field-by-field specs (mirror of ADR-0007) used by validators and authors. | ADR-0007 |

Example files in this tree (`example_*.json`) are real, valid records using **canonical story IDs**
(beat `A1-04`, enemy `sleepless_crane`, Wren's `steady`, `lamp_herb`, branch `BR1`, ending `A`) — copy
them as starting templates.

## IDs are the contract (reuse, never invent)

- **Beats:** `A<act>-<nn>[letter]` exactly as in `docs/story/03_MAIN_STORY.md` (the Beat Ledger).
- **Branches:** `BR1`–`BR4` (`04_BRANCHES_ENDINGS.md`).
- **Quests:** `CQ-<NAME>` / `SQ-<NN|NAME>` / `MA-<NN>` (`05_SIDEQUESTS.md`).
- **Flags:** `UPPER_SNAKE_CASE`, must exist in `flags/flags.json`. **Gating** flags feed UNITY / derived
  flags / the ending resolver; **non-gating** flags (Pell threads, `FIRST_FLIGHT_WON`,
  `RELIGHTING_SHARED`, `HAVEN_RELIT`, `SABLE_RIFT/RECONCILED`, `BRAMBLE_SACRIFICE`, `PIGGY_*`) are flavor
  only and are **proven** never to touch the ending math by a lint test.
- **Content ids:** `lower_snake_case` (`lamp_herb`, `sleepless_crane`).

## How writing flows (pipeline)

1. Add/edit a `.json` in the right folder, reusing canonical IDs.
2. Run the content lint locally: the GUT test `tests/unit/test_content_validation.gd` loads **all**
   data through the validators and reports any error (file, id, field, rule). Layers checked:
   - **Schema** — required fields, types, enums.
   - **References** — every referenced id exists (flags registered, branch `goto`/`merge_beat` real,
     enemy/ability/status/item ids real).
   - **Domain rules** — exactly eight UNITY sources matching `04 §3.2`; resolver reads only gating
     flags; every branch merges at its named beat; the beat graph is connected `A1-01 → A4-07`.
3. Open a `story/…` or `data/…` PR (Conventional Commits). CI re-runs the lint + full suite; an
   independent reviewer checks IDs/flags against the locked story (`03`/`04`). No engine code changes.

## Hard rules

- **No engine numbers in code:** balance values, flag names, and beat IDs live here, not in `.gd`.
- **The story is locked:** beat IDs, `BR1–BR4`, flag names, and the ending gates come straight from
  `03`/`04`; do not renumber or rename without updating those docs and the validators.
- **Offline only:** data is static JSON shipped in the build; nothing here is fetched at runtime.
- **JSON has no comments** — explanations live in `schema/` and the ADRs.
