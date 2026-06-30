# Branches & Endings — "Aetherbound" (working title)

> Built on `00_BRIEF.md` (anchor + Canon rulings), `01_WORLD.md` (world), and `03_MAIN_STORY.md` (beats & ledger). This document is the **branching/merging map**, the **flag model**, and the **four endings**. The conditions here are written to be *deterministic and unit-testable* — they become engine logic.

---

## 1. Design rules (so the game stays buildable)

- Every diverge **merges back** at a named beat. The party may differ in *who* is present and *what was learned*, but the main spine (A1 → A2 → A3 → A4) is single-track between branch nodes.
- Branches change **scenes, locations, recruits, and flags** — never the act structure.
- All consequences are recorded as **flags** (booleans) and one integer **UNITY** counter. The ending is a pure function of the locked flag set (`ENDING_FLAGS_LOCKED` at beat A3-13) plus the player's `FINAL_CHOICE` at A4-06.
- Optional content (Rookwise, unity opportunities) is **missable but never blocking**: the game completes on any path; missing it only narrows which endings are *offered*.

---

## 2. The four branch points

### BR1 — The Two Dying Islands  *(triggers at A2-02 · merges at A2-05)*

Bramble's map-fragment shows two failing skylands, each holding one Skyborn memory-shard. The Driftwing can reach only one before the other sinks.

| Choice | Path contents | Flags set |
| --- | --- | --- |
| **Sail to the Glasswastes** | Glass-Hollow mirror-desert; shelter refugees; recover the **Departure shard** (memory of the Skyborn *stepping out of the world*). Mira joins here. Verdance is lost. | `SAVED_GLASSWASTES=true`, `BRAMBLE_SHARD_DEPARTURE=true`, `MIRA_RECRUITED=true`; `+1 UNITY` if refugees evacuated in time |
| **Sail to Verdance** | Overgrown jungle-island; free trapped villagers from garden-constructs; recover the **Promise shard** (memory of the Warden and the makers' promise). Mira joins here. Glasswastes is lost. | `SAVED_VERDANCE=true`, `BRAMBLE_SHARD_PROMISE=true`, `MIRA_RECRUITED=true`; `+1 UNITY` if villagers freed |

**Merge (A2-05):** Either way Mira is recruited and one shard is held; the other island and its shard are lost to the mist (`ISLAND_LOST=true`). The lost shard can later be **reconstructed by Rookwise** (see BR4) — this is the bridge that keeps Ending D reachable on a single playthrough.

---

### BR2 — The Knight on the Wind  *(triggers at A2-07 · merges at A2-10)*  **[Kestrel-recruitment branch]**

Kestrel is sent to bring the Resonant in. How Wren meets her decides whether she ever defects.

| Choice | Path contents | Flags set |
| --- | --- | --- |
| **Show her the truth** | Stand in the Cinderworks and let Kestrel *see* the conscripted Resonants hollowing on the rigs. Her code was built on a false idea of mercy; her certainty cracks. At A2-10, after Marrow's reveal, she defects. | `KESTREL_DOUBT=true` → at A2-10 `KESTREL_RECRUITED=true`, `+1 UNITY` |
| **Resist & evade** | Out-fly and lose her; she hardens into a relentless but sympathetic pursuer. She does not join; she reappears as an Ascendancy officer in Act III and at the gate. | `KESTREL_PURSUER=true` → `KESTREL_RECRUITED=false` |

**Merge (A2-10):** Both paths converge on the same beat — Kestrel either joins the party or lets them escape while staying loyal. `BR2_RESOLVED=true`. Recruitment requires `KESTREL_DOUBT` (i.e., choosing "show her the truth"); there is no second recruitment window, so this single choice owns `KESTREL_RECRUITED`.

---

### BR3 — The Order's Secret  *(triggers at A3-09 · merges at A3-11)*  **[Lantern Order Stillmere secret: expose vs protect]**

At Stillmere the Order confesses it has always known the Skyborn *departed* (did not die) and hidden the gate-key in the reservoir to protect the people's faith.

| Choice | Path contents | Flags set |
| --- | --- | --- |
| **Expose the secret** | Carry the truth to the whole sky. The Order is shaken and some orthodoxy fractures, but the truth spreads and free sky-folk and truth-seekers rally to an honest cause. Mira chooses honesty over comfort; if you supported her at A3-05 she leads the reform rather than breaking. | `ORDER_SECRET_EXPOSED=true`, `TRUTH_SHARED=true`; `+1 UNITY` **iff** `MIRA_TRUST=true` |
| **Protect the secret** | Keep the confidence; the Order, grateful and intact, allies with the party and lends its lamps, healers, and Stillmere relay to the cause. Mira holds faith and evidence together quietly. | `ORDER_ALLIED=true`; `+1 UNITY` |

**Merge (A3-11):** Both paths converge on the rally before the gate. Each yields a *different shape* of unity (a reformed honest world vs. an intact grateful Order) but both can feed `FACTIONS_UNITED`. `BR3_RESOLVED=true`.

---

### BR4 — The Exile in the Wreck  *(triggers at A3-06 · merges at A3-11)*  **[optional recruit]**

Deep in Thornholt's wrecks waits **Rookwise**, an exiled scholar of forbidden Skyborn lore.

| Choice | Path contents | Flags set |
| --- | --- | --- |
| **Recruit Rookwise** | Free him; he joins as the seventh party member. He can **reconstruct the memory-shard lost at BR1**, completing the Skyborn truth from a single shard. | `ROOKWISE_RECRUITED=true`; `+1 UNITY` |
| **Leave him be** | Skip the wreck; the party of six continues. The lost shard stays lost. | `ROOKWISE_RECRUITED=false` |

**Merge (A3-11):** Optional and non-blocking. Recruiting Rookwise is the usual way to make `WARDEN_TRUTH_WHOLE` true on a one-island run, and is a prerequisite for Ending D. `BR4_RESOLVED=true`.

---

## 3. Flag & variable model

### 3.1 Story flags (booleans)

| Flag | Set at | Meaning |
| --- | --- | --- |
| `RESONANT_REVEALED` | A1-04 | Wren is publicly a Resonant. |
| `BRAMBLE_RECRUITED` | A1-10 | Bramble in party (always by Act II). |
| `MIRA_RECRUITED` | A2-03/04 | Mira in party (always by Act II). |
| `SAVED_GLASSWASTES` / `SAVED_VERDANCE` | A2-03 / A2-04 | BR1 outcome (exactly one true). |
| `BRAMBLE_SHARD_DEPARTURE` | A2-03 | Held shard: Skyborn departed. |
| `BRAMBLE_SHARD_PROMISE` | A2-04 | Held shard: the Warden's promise. |
| `CONSCRIPTS_FREED` | A2-06 | Freed the Cinderworks Resonants (unity). |
| `KESTREL_DOUBT` / `KESTREL_PURSUER` | A2-08 | BR2 first-fork state. |
| `KESTREL_RECRUITED` | A2-10 | Kestrel in party. |
| `HUSH_SURVIVORS_SAVED` | A3-02 | Rescued The Hush survivors (unity). |
| `MIRA_TRUST` | A3-05 | Supported Mira through her crisis. |
| `ROOKWISE_RECRUITED` | A3-06 | BR4 outcome. |
| `ORDER_SECRET_EXPOSED` + `TRUTH_SHARED` | A3-09 | BR3: exposed. |
| `ORDER_ALLIED` | A3-09 | BR3: protected → Order allied. |
| `MARROW_REACHED` | A3-10 | Wren crossed the gap to Marrow. |
| `ALLIES_RALLIED` | A3-11 | Multiple factions answered the call (unity). |
| `MARROW_REDEEMED` / `MARROW_LOST` | A4-03 | Marrow's final resolution. |
| `THANE_PERSUADED` | A4-05 | Thane stood down. |

### 3.2 The UNITY counter

`UNITY` is an integer, starts at `0`, only ever increments. It models how much of the broken world the party has knit back together ("the Unbroken Lamp"). **Eight** sources, `+1` each, all missable except where noted:

| # | Source | Beat | Flag gate |
| --- | --- | --- | --- |
| 1 | Evacuate the BR1 island's refugees in time | A2-03/04 | `SAVED_GLASSWASTES`/`SAVED_VERDANCE` sub-objective |
| 2 | Free the conscripted Resonants | A2-06 | `CONSCRIPTS_FREED` |
| 3 | Recruit Kestrel | A2-10 | `KESTREL_RECRUITED` |
| 4 | Rescue The Hush survivors | A3-02 | `HUSH_SURVIVORS_SAVED` |
| 5 | Recruit Rookwise | A3-06 | `ROOKWISE_RECRUITED` |
| 6 | Resolve BR3 in a unifying way | A3-09 | `ORDER_ALLIED` **or** (`TRUTH_SHARED` **and** `MIRA_TRUST`) |
| 7 | Reach Marrow | A3-10 | `MARROW_REACHED` |
| 8 | Rally multiple factions at the gate | A3-11 | `ALLIES_RALLIED` |

`UNITY` ranges **0–8**. It is **frozen at A3-13** (`ENDING_FLAGS_LOCKED`).

### 3.3 Derived flags (computed, not authored)

```
WARDEN_TRUTH_WHOLE :=
      (BRAMBLE_SHARD_DEPARTURE AND BRAMBLE_SHARD_PROMISE)        // both shards (impossible on one run pre-BR4)
   OR (ROOKWISE_RECRUITED AND (BRAMBLE_SHARD_DEPARTURE OR BRAMBLE_SHARD_PROMISE))  // one shard + Rookwise reconstructs the other

FACTIONS_UNITED :=
      (UNITY >= 5)
  AND KESTREL_RECRUITED
  AND (ORDER_ALLIED OR TRUTH_SHARED)
```

> `FACTIONS_UNITED` deliberately requires the Ascendancy defector (Kestrel), an aligned faith (Order allied or the truth shared), **and** broad goodwill (UNITY ≥ 5). It is the "best/hardest" state from the brief.

---

## 4. The endings

At **A4-06** the Warden presents the final choice. Which options are *offered* is gated; the resulting **ENDING** is a pure function of `FINAL_CHOICE` plus locked flags.

### Option availability at the Wellspring

| Option | Offered iff | Leads to |
| --- | --- | --- |
| **Sleep** | always | Ending B |
| **Take** | always | Ending C |
| **Share** | `FACTIONS_UNITED == true` | Ending A |
| **Wake** (secret) | `WARDEN_TRUTH_WHOLE == true` **AND** `ROOKWISE_RECRUITED == true` **AND** `MARROW_REDEEMED == true` | Ending D |

> Sleep and Take are always available, so the game is always completable. Share and Wake are *earned*. This keeps the four endings deterministic: the player can only pick an offered option.

---

### Ending A — "The Shared Dawn"  *(hopeful; best & hardest)*

**Unlock (exact):** `FINAL_CHOICE == SHARE`.
**Share is offered only when** `FACTIONS_UNITED == true`, i.e. `UNITY >= 5 AND KESTREL_RECRUITED AND (ORDER_ALLIED OR TRUTH_SHARED)`.

**Final-choice presentation:** With the factions gathered behind her — sky-folk, the Order (allied or honest), and Ascendancy defectors — Wren asks the Warden not to hoard or hide the current but to *teach the world to share it.* The Warden offers to redistribute the Wellspring's aether evenly and slowly across every skyland, enough for all if all live within it.

**How it plays out:** Wren tunes the Wellspring to a gentle, even pulse, and across the sky the dying lamps steady — not blazing, but *enough*, everywhere at once. No one city rises while others fall; the Ascendancy's harvesters are turned to charging-ships that carry light to the smallest islands. Thane, if persuaded (`THANE_PERSUADED`), lays down his office and helps; if not, he is gently outvoted by a world that has chosen another way. The party stands on a re-lit Hollowgate at dawn. The Song is heard whole and golden for the first time in the game.

**Theme:** *Saving the world means changing how we live together, not one magic fix.* Stewardship over triage; found family scaled up to a whole sky.

---

### Ending B — "The Long Quiet"  *(bittersweet)*

**Unlock (exact):** `FINAL_CHOICE == SLEEP`. (Always available.)

**Final-choice presentation:** Wren judges that the current can no longer be safely fed, and that draining it — by anyone, for anyone — only spends the last of it faster. She asks the Warden to let the Wellspring sleep for good.

**How it plays out:** One by one the great-lamps dim to a soft, final light and go still — gently, the way the world says of the dead that they "go into the **Long Quiet**." The skylands settle low and slow toward the mist, and a quieter, smaller life begins on the lands that remain: gardens by hand, ships by sail, no aether at all. It is a loss, mourned like a lost friend, but it is also peace — the Hollow fade away with the hunger that made them, and no one is sacrificed to lift anyone else. Bramble's chest-stone dims last; it says it is not afraid. The party watches a low, green world the way you watch a sunset.

**Theme:** The double meaning the brief protects — *the Long Quiet* as the gentle word for death and as a world choosing to let go with grace. Bittersweet, never bleak.

---

### Ending C — "The Ascendant Throne"  *(cautionary; not graphic)*

**Unlock (exact):** `FINAL_CHOICE == TAKE`. (Always available.)

**Final-choice presentation:** Wren (or, if she refuses, Thane at her shoulder) takes the Wellspring's current for the chosen few — to lift the great cities high and let the rest of the sky settle into the dark.

**How it plays out:** The citadel-cities blaze and rise, brighter than ever, on a tide of stolen light — and below them the small islands slip quietly into the mist, lamps going grey one after another. The chosen are saved; the world is not. The final image is the Ascendant cities glittering alone above an empty grey sea, and a single small lamp — Wren's Keeper's Lamp — set down and left behind. No violence is shown; the cost is the silence. If Thane was persuadable but ignored, his is the loneliest face on the throne.

**Theme:** The brief's cautionary path. Hoarding called mercy is still abandonment. A sincere, tragic wrongness — what the heroes spent the whole game refusing.

---

### Ending D — "The Wandering Star"  *(secret)*

**Unlock (exact):** `FINAL_CHOICE == WAKE`.
**Wake is offered only when** `WARDEN_TRUTH_WHOLE == true AND ROOKWISE_RECRUITED == true AND MARROW_REDEEMED == true`.
*(In practice: the full Skyborn truth pieced together, the scholar who reads it aboard, and Marrow brought back from despair — the three deepest threads of the game.)*

**Final-choice presentation:** Knowing now that the Skyborn did not die but *departed* — stepped out of the world and went somewhere — Wren does not command the Warden at all. She *wakes* it as a partner and asks the question no one has asked: *Where did the makers go, and can we follow to ask them how to mend this?*

**How it plays out:** The Warden — the Heartmind — opens its eyes for the first time in an age and answers like someone glad to finally be asked. It stabilizes the Wellspring to a careful, holding pulse (buying the sky time, not forever) and joins the party. Bramble, whole at last, remembers the road the makers took. With Marrow healed and the truth carried openly, Wren and her found family — and the woken Warden — set out past the edge of the known sky to find the vanished Skyborn and bring back the answer the world needs. The Song does not resolve so much as *open*, like a door. A hopeful, mysterious, sequel-shaped horizon.

**Theme:** Hope as curiosity and courage; the world saved not by an ending but by daring to keep asking. The secret reward for players who healed every wound the story offered.

---

## 5. Ending resolver (reference logic)

```text
function resolveEnding(flags, unity, finalChoice):
    # availability (mirror of §4 table)
    canShare = factionsUnited(flags, unity)
    canWake  = flags.WARDEN_TRUTH_WHOLE
               and flags.ROOKWISE_RECRUITED
               and flags.MARROW_REDEEMED

    if finalChoice == SHARE and canShare: return "A"   # The Shared Dawn
    if finalChoice == SLEEP:              return "B"   # The Long Quiet
    if finalChoice == TAKE:               return "C"   # The Ascendant Throne
    if finalChoice == WAKE and canWake:   return "D"   # The Wandering Star (secret)
    # SHARE/WAKE are never presented unless their gate is true,
    # so no fallback is reachable; assert for safety.

function factionsUnited(flags, unity):
    return unity >= 5
       and flags.KESTREL_RECRUITED
       and (flags.ORDER_ALLIED or flags.TRUTH_SHARED)

# WARDEN_TRUTH_WHOLE (derived at A3-13):
#   (SHARD_DEPARTURE and SHARD_PROMISE)
#   or (ROOKWISE_RECRUITED and (SHARD_DEPARTURE or SHARD_PROMISE))
```

---

## 6. ASCII story-graph

```
                              ┌──────────────────────────┐
                              │  ACT I — Keeper's Lamp     │
                              │  A1-01 … A1-12 (linear)    │
                              │  recruit: Sable,Tam,Bramble│
                              └────────────┬───────────────┘
                                           │  MAIN_QUEST_WELLSPRING
                                           ▼
                              ┌──────────────────────────┐
                              │  ACT II — Sinking Roads    │
                              │  A2-01 (recruit Mira soon) │
                              └────────────┬───────────────┘
                                           │
                              ╔════════════╧════════════╗  BR1 @ A2-02
                              ▼                         ▼
                   ┌───────────────────┐     ┌───────────────────┐
                   │ A2-03 Glasswastes │     │ A2-04 Verdance     │
                   │ SHARD_DEPARTURE   │     │ SHARD_PROMISE      │
                   │ SAVED_GLASSWASTES │     │ SAVED_VERDANCE     │
                   └─────────┬─────────┘     └─────────┬─────────┘
                             ╚════════════╤════════════╝  merge @ A2-05
                                          ▼
                                   A2-06 Cinderworks
                                          │
                              ╔═══════════╧═══════════╗  BR2 @ A2-07
                              ▼                       ▼
                   ┌───────────────────┐   ┌───────────────────┐
                   │ Show the truth    │   │ Resist & evade     │
                   │ KESTREL_DOUBT     │   │ KESTREL_PURSUER    │
                   └─────────┬─────────┘   └─────────┬─────────┘
                             │ A2-09 Marrow boss     │
                             ╚══════════╤════════════╝  merge @ A2-10
                                        │  KESTREL_RECRUITED?  (+1 UNITY if yes)
                                        ▼
                          A2-11 gate-relay  ▶  A2-12 ✸ SECOND SUNDERING ✸
                                        │        (map breaks, party scattered)
                                        ▼
                              ┌──────────────────────────┐
                              │  ACT III — Fading World    │
                              │ A3-01 alone → A3-02 Hush   │
                              │ reunite Sable/Tam/Mira     │
                              └────────────┬───────────────┘
                                           │
                              ╔════════════╧════════════╗  BR4 @ A3-06 (optional)
                              ▼                         ▼
                     ┌─────────────────┐       ┌─────────────────┐
                     │ Recruit Rookwise│       │ Leave him be    │
                     │ ROOKWISE=true   │       │ ROOKWISE=false  │
                     └────────┬────────┘       └────────┬────────┘
                              ╚═══════════╤═════════════╝
                                          ▼   A3-08 Stillmere secret
                              ╔═══════════╧═══════════╗  BR3 @ A3-09
                              ▼                       ▼
                   ┌───────────────────┐   ┌───────────────────┐
                   │ Expose            │   │ Protect            │
                   │ TRUTH_SHARED      │   │ ORDER_ALLIED       │
                   └─────────┬─────────┘   └─────────┬─────────┘
                             │ A3-10 Marrow in grey  │
                             ╚══════════╤════════════╝  merge @ A3-11 (allies rally)
                                        ▼   A3-12 gate opens → A3-13 LOCK FLAGS
                              ┌──────────────────────────┐
                              │  ACT IV — The Wellspring   │
                              │  A4-01…A4-05  →  A4-06      │
                              │        THE CHOICE          │
                              └─┬────────┬────────┬───────┬┘
                                │        │        │       │
                     (canShare) │        │        │       │ (canWake: truth+Rookwise+Marrow)
                                ▼        ▼        ▼       ▼
                            ┌───────┐┌───────┐┌───────┐┌───────────┐
                            │  A    ││  B    ││  C    ││  D (secret)│
                            │Shared ││ Long  ││Ascend ││ Wandering  │
                            │ Dawn  ││ Quiet ││Throne ││   Star     │
                            └───────┘└───────┘└───────┘└───────────┘
```

---

*Continuity owner: `07_CONTINUITY_NOTES.md`. Full dialogue for each branch node and each ending: `06_SCRIPT_KEY_SCENES.md`.*
