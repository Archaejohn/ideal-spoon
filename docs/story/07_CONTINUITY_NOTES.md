# Continuity & Consistency Notes — "Aetherbound" (working title)

> **Editor's pass.** Covers `00_BRIEF.md` → `06_SCRIPT_KEY_SCENES.md` (the full story bible). This document records every inconsistency found, the fix applied (or why it was only flagged), a **canonical quick-facts reference table** every future writer/engineer must match, and the **open issues** left for the Owner. Edits were kept targeted and conservative — no creative intent was changed.

---

## A. Inconsistencies found — fixes applied & flags

### A1. Ship name: "Gull's Mercy" vs "Driftwing" — **FIXED** ✅
- **Owner ruling (binding):** the canonical ship name is **"Driftwing."**
- **Problem:** `03_MAIN_STORY.md` (the engine-contract Beat Ledger, A1-06 onward), `04_BRANCHES_ENDINGS.md`, and the entire `06` script all used **Driftwing**. `02_CHARACTERS.md` used **"Gull's Mercy"** in three places (Sable's snapshot, gameplay identity, and the **Full Burn** ability).
- **Fix applied:**
  - `02_CHARACTERS.md` — all three "Gull's Mercy" references changed to **"Driftwing"** (Sable snapshot line; "the *Driftwing* is effectively a party member"; "Full Burn — calls a strafing pass from the *Driftwing*").
  - `06_SCRIPT_KEY_SCENES.md` — the closing editor note (line ~1010) updated from "flag a reconcile if 02's 'Gull's Mercy' is preferred" to record that the ship is canonically the **Driftwing** per Owner ruling and that 02 has been reconciled.
- **Related:** `08_REVIEW.md` items #46 and #73 (which flag this very bug) are now **resolved** by these edits. Left 08 untouched (it is the reviewer's record); the reviewer can check those items off.
- **Note for engineers:** the Driftwing is destroyed at **A2-12** (`DRIFTWING_LOST`); from **A3-03** (`HAS_SHIP`) Sable flies a patched-together replacement (unnamed in canon). Sable's ship-flavored abilities (Full Burn, "ship as party member") implicitly retarget to whichever hull she currently flies. (Minor flavor, not a contradiction — see Open Issue O3.)

### A2. Character-name collision: two "Pell"s — **FIXED** ✅
- **Problem:** **Keeper Pell** is Wren's beloved elderly master on Meadowmoor (`02`, `03`, `06`). `05_SIDEQUESTS.md` (CQ-KESTREL, "The Names on the Wall") independently named **Kestrel's teenage squire "Pell."** Two unrelated characters sharing one name is a real continuity hazard, especially for a 10-year-old reader.
- **Fix applied:** renamed Kestrel's squire **Pell → "Finch"** in all three CQ-KESTREL references (hook, step 3, choice/twist). "Finch" is original, pronounceable, and fits the Ascendancy sky-knight aviary naming pattern (cf. Kestrel, Corvus) while staying clearly distinct from Wren's master. "Keeper Pell" now refers to exactly one person across the bible.

### A3. Keeper Pell's title: "Master Pell" vs "Keeper Pell" — **FIXED** ✅
- **Problem:** `02_CHARACTERS.md` called Wren's master "**Master Pell**," while the canonical ledger (`03`) and the script (`06`) call him "**Keeper Pell**" throughout.
- **Fix applied:** `02_CHARACTERS.md` — "old **Master** Pell, the island's lamp-keeper" → "old **Keeper** Pell, the island's lamp-keeper." Title now consistent everywhere. (Wren still refers to him affectionately as "my master"; that is role/relationship language, not a name, and was left as-is.)

### A4. Ending D gating: side-quest claims vs the authoritative resolver — **FLAGGED** ⚠️ (see Open Issue O1)
- Not edited — resolving it is a design decision for the Owner. Details below.

### A5. Stillmere accessibility timing: Act II side content vs Act III main-quest unlock — **FLAGGED** ⚠️ (see Open Issue O2)
- Not edited — needs a one-line Owner/engineer clarification rather than a content change.

---

## B. Items checked and found CONSISTENT (no edit needed)

- **Ages** — Wren 14, Sable 38, Tam 14, Mira 19, Kestrel 27, Bramble unknown (Skyborn-era), Rookwise 71, Thane 60, Marrow ~30. Consistent across `00`/`02`/`03`.
- **The eight canon skylands** — identical set and spellings in `01` §1 and `05` (How-to-read). `03` and `06` use only these.
- **Beat IDs** — every beat ID tagged in `06` (A1-01, A1-04, A1-06, A1-10, A2-07…A2-10, A2-12, A3-08…A3-10, A4-06, A4-07) matches `03`'s Beat Ledger exactly. `05` quests reference real skylands/acts.
- **Heart-pass beat additions (consistent)** — the new beats **A1-06b** (Pell's habit), **A3-02b/A3-02c** (Pell reunion + loss at The Hush), **A3-03b/A3-03c** (Sable–Wren fracture + reconcile), and **A4-06b** (Bramble steps forward) are scripted in `06` and present in `03`'s Beat Ledger with their flags. They slot **between** existing beats and **renumber nothing**; no existing beat ID was changed or removed.
- **Flag names** — all flags used in `06` (`SABLE_RECRUITED`, `TAM_RECRUITED`, `HAS_KEEPERS_LAMP`, `BRAMBLE_RECRUITED`, `KESTREL_DOUBT`/`KESTREL_PURSUER`, `BOSS_MARROW_CLEARED`, `DRAIN_PLAN_KNOWN`, `BR2_RESOLVED`, `KESTREL_RECRUITED`, `SECOND_SUNDERING`, `DRIFTWING_LOST`, `ORDER_SECRET_LEARNED`, `ORDER_SECRET_EXPOSED`+`TRUTH_SHARED`/`ORDER_ALLIED`, `MARROW_REACHED`/`MARROW_REDEEMED`, `FINAL_CHOICE`) match `03`'s ledger and `04`'s flag model.
- **Endings unlock logic** — `04` §4 (availability table + resolver pseudocode) is internally consistent with `03`'s A4-06 options and `06`'s A4-06/A4-07 scripted gates. Sleep/Take always offered (game always completable); Share gated on `FACTIONS_UNITED`; Wake (secret) gated on `WARDEN_TRUTH_WHOLE AND ROOKWISE_RECRUITED AND MARROW_REDEEMED`. `WARDEN_TRUTH_WHOLE` correctly requires Rookwise on a single-island run (only one shard obtainable via BR1) — the redundancy with the explicit `ROOKWISE_RECRUITED` clause is harmless.
- **Branch trigger/merge beats** — BR1 (A2-02→A2-05), BR2 (A2-07→A2-10), BR3 (A3-09→A3-11), BR4 (A3-06→A3-11) agree between `03` (branch table + ledger) and `04`.
- **Who is recruited where** — Sable/Tam (A1-06), Bramble (A1-10), Mira (A2-03/04), Kestrel (A2-10, BR2, optional), Rookwise (A3-06, BR4, optional). Matches `00` skeleton.
- **Marrow's tragedy** — conscripted natural Resonant burned out by Ascendancy rigs → Songsickness/hollowing. Consistent with Canon Ruling #2 across `00`/`01`/`02`/`03`/`05` (SQ-08 reuses it as a gentle echo, not a duplicate).
- **Pronouns** — Marrow consistently they/them; Kestrel she/her; Bramble "it." Consistent.
- **Terminology** — Songsickness, wellstone, Tinplate automatons, Glass Hollow, garden-constructs, Long Quiet, Heartmind/Warden all spelled and used consistently.
- **Age-appropriateness wording** — loss is consistently shown as "the Long Quiet" / fading to light (Keeper Pell's onscreen fade at **A3-02c**, shown as a lamp easing down at dawn; Bramble's gentle gift in Endings A/B/C, *"I am not afraid"*; Ending B); no gore; villains are sincere/grieving (Thane, Marrow, the foreman in SQ-08, the salvagers in SQ-04). Hollow are pitied, never demonized. **The former A3-10 ledge/fall framing for Marrow was re-staged** to "giving up / surrendering to the Hollow-quiet," with no jump/fall/ledge imagery — see `06` A3-10 safety note. No slips found. (Deep content-rating judgment left to the reviewer per brief.)

---

## C. CANONICAL QUICK-FACTS REFERENCE TABLE
> **Future writers/engineers must match these exactly.** Anything conflicting with this table is a bug.

### C1. Protagonist & party
| Name | Age | Role / battle identity | Recruited | Notes |
| --- | --- | --- | --- | --- |
| **Wren** | 14 | Apprentice aether-tender; hidden **Resonant**. Support/Utility ("Song": Listen/Steady/Shape; resource = **Breath**) | A1 (protagonist) | Heart of the story |
| **Sable Vance** | 38 | Skyship captain & salvager. Gunner / Skyship tricks | A1-06 | Master of the **Driftwing** |
| **Tam Brightgear** | 14 | Self-taught inventor. Gadgets / Items | A1-06 | Wren's best friend |
| **Mira** | 19 | Lantern Order healer. Healer / Wards | A2-03 or A2-04 | Raised at Stillmere |
| **Bramble** | unknown (Skyborn-era) | Awakened Skyborn tender-construct. Adaptive / Relic loadout | A1-10 | Pronoun "it"; non-human |
| **Kestrel** | 27 | Defecting Ascendancy sky-knight. Tank / Counter-bruiser | A2-10 **(optional, BR2 "show her the truth")** | Former squire: **Finch** |
| **Rookwise** | 71 | Exiled scholar of forbidden Skyborn lore. Lore-Mage / Debuff | A3-06 **(optional, BR4)** | 7th member when recruited |

### C2. Antagonists / key NPCs
| Name | Age | Role |
| --- | --- | --- |
| **High Regent Corvus Thane** | 60 | Leader of the Ascendancy; sincere, grieving, wrong |
| **Marrow** | ~30 | Thane's enforcer; conscripted Resonant burned out by rigs; Wren's dark mirror |
| **The Warden (Heartmind)** | ageless | Dormant intelligence in the Wellspring; the final *choice*, not a boss |
| **Keeper Pell** | elderly | Wren's master & Meadowmoor lamp-keeper — a **non-Resonant** keeper (Owner ruling O4). Recurring emotional thread (A1-01, A1-05/06, **A1-06b**). Evacuated Meadowmoor to **The Hush**, where he reunites with Wren (**A3-02b**) and is lost keeping the last lamp lit *by hand* as he fades into the Long Quiet (**A3-02c**). His habit/saying and the **Keeper's Lamp** pay off in the finale (`PELL_REMEMBERED`). |

### C3. Ship
- **Driftwing** — Sable's skyship (canonical, single name). Destroyed at **A2-12** (`DRIFTWING_LOST`); replaced by an unnamed patched-together hull from **A3-03** (`HAS_SHIP`).

### C4. The eight canon skylands
1. **Hollowgate** — hub skytown (beached Skyborn cathedral-ship)
2. **Meadowmoor** — Wren's home (farming island, failing lamp)
3. **The Glasswastes** — fused mirror-glass desert; Glass Hollow
4. **Verdance** — overgrown jungle-island; garden-constructs
5. **The Cinderworks** — Ascendancy industrial island
6. **Thornholt** — free salvagers' shantytown
7. **Stillmere** — Lantern Order monastery (mirror-reservoir relay)
8. **The Hush** — skyland half-claimed by the Fading (post-cataclysm)

*(Beneath all, reached only in Act IV: the descent to the **Wellspring**.)*

### C5. The four branch points
| Branch | Triggers | Merges | Choice |
| --- | --- | --- | --- |
| **BR1** | A2-02 | A2-05 | Glasswastes (Departure shard) vs Verdance (Promise shard) — which island & shard you save |
| **BR2** | A2-07 | A2-10 | Show Kestrel the truth (`KESTREL_DOUBT`→recruit) vs Resist & evade (`KESTREL_PURSUER`) |
| **BR3** | A3-09 | A3-11 | Expose the Order's secret (`TRUTH_SHARED`) vs Protect it (`ORDER_ALLIED`) |
| **BR4** | A3-06 | A3-11 | Recruit Rookwise vs Leave him be (optional) |

### C6. The four endings & exact unlock conditions
| Ending | `FINAL_CHOICE` | Offered iff |
| --- | --- | --- |
| **A — The Shared Dawn** (hopeful; best/hardest) | `SHARE` | `FACTIONS_UNITED` = `UNITY ≥ 5 AND KESTREL_RECRUITED AND (ORDER_ALLIED OR TRUTH_SHARED)` |
| **B — The Long Quiet** (bittersweet) | `SLEEP` | always |
| **C — The Ascendant Throne** (cautionary) | `TAKE` | always |
| **D — The Wandering Star** (secret) | `WAKE` | `WARDEN_TRUTH_WHOLE AND ROOKWISE_RECRUITED AND MARROW_REDEEMED` |

- **Derived:** `WARDEN_TRUTH_WHOLE := (SHARD_DEPARTURE AND SHARD_PROMISE) OR (ROOKWISE_RECRUITED AND (SHARD_DEPARTURE OR SHARD_PROMISE))`. Locked at **A3-13** (`ENDING_FLAGS_LOCKED`).
- **UNITY** = integer 0–8, increment-only, frozen at A3-13. Eight sources (BR1 evac, free conscripts, recruit Kestrel, rescue The Hush survivors, recruit Rookwise, unifying BR3, reach Marrow, rally factions).

### C7. Key flag names (must match exactly)
`GAME_START` · `RESONANT_REVEALED` · `SABLE_RECRUITED` · `TAM_RECRUITED` · `HAS_KEEPERS_LAMP` · `BRAMBLE_RECRUITED` · `MAIN_QUEST_WELLSPRING` · `MARROW_SEEN` · `MIRA_RECRUITED` · `SAVED_GLASSWASTES` / `SAVED_VERDANCE` · `BRAMBLE_SHARD_DEPARTURE` / `BRAMBLE_SHARD_PROMISE` · `ISLAND_LOST` · `CONSCRIPTS_FREED` · `KESTREL_DOUBT` / `KESTREL_PURSUER` · `KESTREL_RECRUITED` · `BOSS_MARROW_CLEARED` · `DRAIN_PLAN_KNOWN` · `SECOND_SUNDERING` · `DRIFTWING_LOST` · `PARTY_SCATTERED` · `HUSH_SURVIVORS_SAVED` · `SABLE_REJOINED` / `HAS_SHIP` · `TAM_REJOINED` · `MIRA_REJOINED` / `MIRA_TRUST` · `ROOKWISE_RECRUITED` · `ORDER_SECRET_LEARNED` · `ORDER_SECRET_EXPOSED` + `TRUTH_SHARED` / `ORDER_ALLIED` · `MARROW_REACHED` · `ALLIES_RALLIED` · `GATE_OPEN` / `PARTY_REUNITED` · `BRAMBLE_WHOLE` · `ENDING_FLAGS_LOCKED` · `WELLSPRING_REACHED` · `WARDEN_AWAKE` / `WARDEN_TRUTH_WHOLE` · `MARROW_REDEEMED` / `MARROW_LOST` · `THANE_PERSUADED` · `FINAL_CHOICE` ∈ {`SHARE`,`SLEEP`,`TAKE`,`WAKE`} · `ENDING` ∈ {`A`,`B`,`C`,`D`}.

**Heart-pass flags (non-gating — they do NOT feed UNITY, the derived flags, or the ending resolver; they only drive scene flavor and callback lines):** `PELL_RITUAL_TAUGHT` (A1-06b) · `PELL_FOUND` (A3-02b) · `PELL_LOST` + `PELL_REMEMBERED` (A3-02c) · `SABLE_RIFT` (A3-03b) · `SABLE_RECONCILED` (A3-03c) · `BRAMBLE_SACRIFICE` (A4-06b; set **iff** `FINAL_CHOICE` ∈ {`SHARE`,`SLEEP`,`TAKE`} — an outcome flag derived from a choice already committed, never a gate). No existing flag name or ending-unlock condition was changed.

---

## D. Open issues for the Owner

### O1. Ending D gating — **RESOLVED ✅** (Owner ruling: option (a), flavor only)
`04_BRANCHES_ENDINGS.md` is the authoritative, unit-testable resolver and gates **Ending D (Wake)** purely on `WARDEN_TRUTH_WHOLE AND ROOKWISE_RECRUITED AND MARROW_REDEEMED`. But `05_SIDEQUESTS.md` states as hard requirements that **Ending D** also needs:
- **MA-01 "Song Fragments"** complete ("The Whole Song… key requirement for the secret Ending D"), and
- **CQ-BRAMBLE** complete ("Completing the Song is required for the secret Ending D thread"; **Completed Heart-Stone** = "required key item for Ending D").

These two extra gates do **not** appear in `04`'s resolver. **Recommendation:** Owner to decide one of —
(a) **Flavor only:** soften `05`'s wording so MA-01/CQ-BRAMBLE *narratively accompany* but do not *gate* Ending D (keeps `04` as the single source of truth); or
(b) **Real gates:** add `SONG_WHOLE` and `BRAMBLE_HEARTSTONE` (or fold them into `WARDEN_TRUTH_WHOLE`/`BRAMBLE_WHOLE`) to `04`'s Wake condition and the resolver.
**Resolution applied:** Owner chose **(a)**. `04` remains the single source of truth and was **not** touched in its Wake gate. `05`'s MA-01, CQ-BRAMBLE, and the "Ending hooks" note were reworded so the Whole Song / Completed Heart-Stone *accompany and support* Ending D as **flavor, not hard gates**. No new gate added.

### O2. Stillmere accessibility: Act II vs Act III — **RESOLVED ✅**
Main story gates the **Stillmere** main-quest beat to Act III (`STILLMERE_UNLOCKED` at **A3-07**), and Act II's location list in `03` does not include Stillmere. But `05` places Stillmere-adjacent side content in **Act II** (CQ-MIRA unlock "Act II–III, after first Stillmere visit"; SQ-05 "Near Stillmere," Act II–III) and MA-01 lists a Stillmere Song Fragment collectible from Act II. **Likely intent:** the *island* is freely visitable by ship for side content earlier, while `STILLMERE_UNLOCKED` gates only the *main-quest reservoir/secret/gate-key* beat. **Recommendation:** add one clarifying line to `03`/`04` (and/or rename the flag to `STILLMERE_SECRET_UNLOCKED`) so engineers don't lock the whole island until A3-07. The same "skylands remain revisitable for side content" assumption underlies CQ-WREN (return to Meadowmoor in Act III) — worth stating once as a global rule. **Resolution applied:** a one-line **"Revisitable skylands (timing rule)"** note was added to `05`'s continuity & scope notes — all eight skylands are freely revisitable by ship for *side content* from first reach; only the *main-quest* Stillmere reservoir/secret/gate-key beat gates at **A3-07** (`STILLMERE_UNLOCKED`). This makes CQ-MIRA / SQ-05 / MA-01 Act II Stillmere content and CQ-WREN's Act III Meadowmoor return all consistent.

### O3. Party-size counting assumes the Kestrel-recruited path — **RESOLVED ✅**
`04` BR4 says recruiting Rookwise makes him "the **seventh** party member" and leaving him means "the party of **six** continues." Those counts hold only if **Kestrel was recruited** (BR2 fork A). On the `KESTREL_PURSUER` path the counts are off by one (five core + Rookwise = sixth). Cosmetic prose only; no mechanical impact. **Resolution applied:** `04`'s BR4 table was reworded to be path-agnostic ("an additional party member — the seventh if Kestrel was recruited, otherwise the sixth"; "the party continues without him").

### O4. Was Keeper Pell himself a Resonant? — **RESOLVED ✅** (Owner: NO, non-Resonant keeper)
CQ-WREN (`05`) says Pell "spent his **last steadiness calming the Hollow** so the village could be evacuated." "Steadiness" is Wren's Resonant resource (Breath) and *calming/re-tuning* Hollow is described in `01` as specifically a **Resonant** act — which could imply Pell was also a Resonant. That would slightly complicate the "rare, hidden Resonant" premise (though `06` A1-01 confirms Pell *knew* about Wren's gift). It can also be read innocuously as a keeper's hand-craft (driving off / out-waiting Hollow, stretching a stone) plus loose use of "steadiness." **Recommendation:** Owner to confirm whether Pell was a non-Resonant keeper (preferred, keeps Resonants rare) and, if so, lightly reword CQ-WREN step 3 to avoid implying a Song. **Resolution applied:** Owner confirms **Pell is NOT a Resonant.** CQ-WREN step 3 was reworded so his keeping is plain hand-craft (driving off / out-waiting Hollow, stretching the stone "by candle, cloth, and patience — no Song; Pell was never a Resonant"). The new main-story loss (A3-02c) likewise states he keeps the last lamp lit "by hand… a keeper's plain hand-craft, no Song." Resonants stay rare.

---

## E. Heart-pass note (Lead Writer)

A "heart pass" added/strengthened four emotional threads **without touching the engine contract** (no existing beat ID, flag, UNITY source, derived flag, or ending-unlock condition changed):
1. **Keeper Pell** is now a recurring father-thread (A1-01/05/06, new **A1-06b**) who returns and is gently, permanently lost at The Hush (new **A3-02b/A3-02c**), fading into the Long Quiet keeping a lamp lit *by hand*. Loss is shown as fading-to-light, never gore.
2. **Bramble** is the finale's fulcrum (new **A4-06b**): it gives the last of itself in Endings A/B/C ("I am not afraid") and is instead made **whole** only on secret Ending D. New non-gating flag `BRAMBLE_SACRIFICE`.
3. **Sable vs. Wren** fracture-and-reconcile (new **A3-03b/A3-03c**) dramatizes hoarding-vs-sharing between two who love each other.
4. **A3-10 safety re-stage** (`06`): all ledge/jump/fall imagery removed; Marrow now *gives up* / surrenders to the Hollow-quiet and is reached by "one note." Redemption and mirror preserved.

---

*Continuity owner: this file (`07_CONTINUITY_NOTES.md`). Source of truth for branching/flags/endings: `04_BRANCHES_ENDINGS.md`; for beats/IDs: `03_MAIN_STORY.md`. Reviewer's pass: `08_REVIEW.md` (ship-name items #46/#73 now resolved).*
