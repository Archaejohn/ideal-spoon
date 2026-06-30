# Content & Quality Review — "Aetherbound"

> Independent review of the story bible (`00`–`06`). Reviewer did not write any of this material. Scope: age-appropriateness, reading level, narrative quality, originality, and completeness. This file is the only one edited.

---

## OVERALL VERDICT: **APPROVE WITH MINOR FIXES**

This is genuinely strong, professional work. The world is coherent and original-feeling, the cast is distinct and warmly drawn, the branch/flag model is unusually rigorous (it reads like something an engineer could build against tomorrow), and the script lands real emotional beats without ever getting gory or mean. It earns the "FF VI ensemble" ambition more than most pitches do.

It is **not** a clean APPROVE for one reason: a single beat (Marrow at the cliff, `A3-10`) crosses the brief's own "no mature themes" hard line by staging what reads as suicide ideation, and there are a handful of small continuity/spec bugs. None of these are deep or structural. Fix the items below and this is a confident APPROVE.

---

## 1. Age-appropriateness — **7/10**

**What works (and works well):**
- **Villains are sincere, not cruel.** Thane "never raves; he *explains*" (`02`, line 206), and the Ascendancy officer says "I take no joy in it, keeper. That changes nothing" (`06`, A1-04). This is exactly the brief's mandate, executed.
- **Death is handled gently.** Keeper Pell's loss is now shown onscreen (`06`, A3-02c) as a lamp easing gently down "the way you'd set down a lamp you no longer need because morning came" — fading-to-light, never gore, framed as "the Long Quiet"; Bramble's finale gift (Endings A/B/C) is the same gentle fade ("I am not afraid"). Endings B and C show loss as lamps "fading to grey," explicitly "No violence is shown. The cost is the silence" (`06`, Ending C).
- **Combat is non-graphic.** Hollow are "absences — silhouettes rimmed in faint cold light, ash-and-static, never bloody" (`01`, §8).

**Flags — specific lines/beats to address:**

- **MUST address — `A3-10`, Marrow at the cliff.** Stage direction: "They look like someone deciding whether to step off." Then WREN: "I think you came out here to fall." MARROW: "...And if I did?" WREN: "Then I came to ask you not to." (`06`, lines 726–737). However sensitively written — and it *is* beautifully written — this is unmistakably a character poised to take their own life, being talked back from the edge. The brief's hard constraint is "**no mature themes**" (`00`, line 12). A 10-year-old will read this as exactly what it is. **Suggested softening:** keep all the despair and the "one note" redemption, but reframe the physical staging away from a literal ledge-jump. Marrow could be at the grey edge intending to "walk into the mist and let the quiet take me" / "give up and let myself go Hollow for good" — surrender rather than a jump. That preserves the emotional stakes (despair, giving up, being reached) while removing the explicit self-harm tableau.
  - **ADDRESSED ✅ (Lead Writer heart pass):** A3-10 was re-staged exactly along these lines. Marrow is now in a drowned grey basin *surrendering to the Hollow-quiet* — "letting the silence finish it… to go still, like them" — with **no ledge, edge, jump, or fall imagery**. Wren reaches them with "one note." The "fall" line became "I think you came out here to give up. To let the silence take the rest of you," and "Come down off the cliff" became "Come back out of the quiet." See the safety note at the top of `06` §8.

- **Minor — intensity of the Second Sundering (`A2-12`).** Islands "shudder, tilt, and begin to *fall*… like candles being snuffed," the party is "flung apart," "Sable's hand closing on empty air where Wren was" (`06`, lines 575, 593). This is appropriately non-gory but is genuinely intense and frightening for the youngest end of the audience. It's within bounds for the genre (comparable to a big animated-film disaster scene) and I would **keep it** — but the team should be aware it's the scariest moment in the game and pace the lead-out (the quiet Act III opening) to let kids decompress.

- **Minor — conscription/forced-labor of children.** Wren (14) is targeted for conscription, and Marrow "was you. Smaller, even" when the rigs broke them (`02`, line 228); the Cinderworks shows Resonants "worked past breaking… Songsick, hollowing" (`06`, A2-07). This is heavy but handled non-graphically and is consistent with how classic all-ages RPGs treat empire/exploitation. **Acceptable as-is.**

Net: the material is overwhelmingly on-target and handled with real care. The score is held at 7 only because the cliff beat genuinely breaches a *stated hard constraint*, not a soft preference.

## 2. Reading level — **8/10**

The **player-facing dialogue** is impressively pitched: short lines, concrete images, gentle rhythm ("Brave isn't a thing you *are*… It's a thing you do, scared, one more time," `06`, A1-06). A 10-year-old at a 6th-grade level can read the vast majority of it comfortably.

**Flags:**
- A few stretch words in dialogue: "requisitioned" (A1-03) — though it's immediately reframed by Pell ("That's robbing a dying man's last breath"), so context carries it; "the arithmetic of mercy" (Thane, recurring) — "arithmetic" is fine, the abstraction is a slight reach but evocative; "order without conscience is just a tidier cruelty" (Kestrel) — "conscience" is on-level, the phrase is abstract. These are **acceptable** and even good vocabulary-stretchers; flag only if playtesting shows kids stumbling. Suggestion if simplifying: officer could say "claimed for the greater good" instead of "requisitioned."
- **Important distinction:** the *narration and stage directions* across `01`–`06` use clearly above-6th-grade vocabulary ("austere," "immaculate," "digressive," "reverent," "owlish"). That is correct — those are production notes for adult designers/artists, not player text. The team should just ensure none of that register leaks into on-screen flavor text. No change needed to the docs themselves.

## 3. Narrative quality & coherence — **8/10**

This is the strongest dimension. The cast voices are distinct on the page (you can tell a Sable line from a Mira line with the name removed), the arcs are real (Wren timid→deciding, Sable cynic→believer, Kestrel duty→conscience, Bramble tool→person), and the found-family thesis is genuinely felt, especially the scatter-and-reunion structure of Acts II–III. The flag/UNITY/derived-flag model (`04`) is rigorous and testable, and the ending resolver is clean. Emotional weight is there: A1-06 (Pell's goodbye), A2-12 (the Sundering), and the four endings all land.

**Plot holes / dropped threads / spec gaps:**
- **`MARROW_REDEEMED` has no exact predicate.** `04` repeatedly promises conditions are "deterministic and unit-testable," yet the actual gate for redemption is left as prose: A3-10 "outcome depends on cumulative hope shown across the game (UNITY / kindness flags)" and A4-03 resolves "by the locked flags" — but no formula is given (`06`, line 751; `03`, A4-03). Since `MARROW_REDEEMED` is a hard prerequisite for the secret Ending D, this is a real gap. **Define it** (e.g., `MARROW_REDEEMED := MARROW_REACHED AND UNITY >= N`).
- **Ship name inconsistency.** `02_CHARACTERS.md` names Sable's ship the **"Gull's Mercy"** (line 48, 61), while `03`'s Beat Ledger and the entire `06` script call it the **"Driftwing"** (A1-06 onward). The script's own closing note already flags this (`06`, line 1010). One name, everywhere.
- **Name collision: "Pell."** Wren's beloved master is **Keeper Pell**, but CQ-KESTREL introduces Kestrel's former squire, "a teenager named **Pell**" (`05`, line 94). Two emotionally significant characters sharing a name will confuse players. Rename the squire.
- **Minor — the "Keepers" faction is underused.** Introduced as Wren's whole tradition (`01`, §4 "The Keepers"), but only Pell ever embodies it. Either lean into it (a late beat where Wren meets another Keeper) or accept it as flavor.
- **Minor — Larkfall Keel persistence.** CQ-SABLE (Act II) rewards a ship upgrade to the Driftwing, which is then destroyed at A2-12. Clarify whether the upgrade/benefit carries to the Act III replacement hull so the reward isn't silently voided.

## 4. Originality — **7/10**

The naming and worldbuilding are largely original and pleasant: Meadowmoor, Hollowgate, Glasswastes, Cinderworks, Thornholt, Stillmere, the cast names. No character/plot is lifted wholesale. But there are a few echoes worth conscious decisions on:

- **"Hollow" (creatures + "hollowing"/"Hollow-touched").** This is the closest resemblance. *Dark Souls* uses "Hollow"/"going Hollow" for undead who lose their self/humanity — conceptually very near to this game's husks-emptied-of-essence and a Resonant who "hollows" from burnout. Different mechanics, generic word, almost certainly not infringing — but it's the one term I'd consider renaming for distinctiveness (e.g., "Husks," "the Faded," "the Quiet-touched," "Wisps").
- **"Aether" + lifeforce-harvested-by-an-industrial-empire.** Thematically adjacent to *Final Fantasy VII*'s Mako/Lifestream and Shinra. "Aether" is also heavily used by *FF XIV*. It's a public-domain word (classical element) and a broad trope the brief openly invites, so low legal concern — but be aware the "empire drains the planet's life-energy" frame is well-trodden; the original spin (stewardship-vs-triage, the *choice* finale) is what differentiates it, and that's solid.
- **"Skyborn"** is the title of an existing 2014 indie RPG. Generic compound, different game, low concern — note for awareness.
- **Internal-doc shorthand only:** `00_BRIEF.md` (line 9) describes the magic as "espers/magitek-style." "Esper" and "Magitek" are Final Fantasy terms. They appear **only** as internal reference shorthand and never in player-facing content (confirmed — the script uses none of them). Just ensure they stay out of the game text.

None of these rise to a legal worry; the strongest recommendation is to reconsider "Hollow."

## 5. Completeness for a full-length RPG — **9/10**

Very complete for a story bible. Four full acts with a ~50-entry Beat Ledger (`03`), 4 diverge/merge branch points that all merge cleanly, 4 distinct and well-differentiated endings with exact unlock logic and reference resolver code (`04`), 6 companion quests + 8 town/world quests + 2 mastery arcs = 16 side quests, all theme-tied and scoped as buildable (`05`), and full scripted dialogue for every key beat, branch fork, and ending (`06`). Eight realized skylands give a real travel arc.

**Thin spots (all expected at bible stage):** only the *key* scenes are scripted — the connective NPC dialogue, dungeon layouts, and encounter tables remain to be authored downstream; the optional Rookwise has a lighter arc than the core six; the Keepers faction (see §3) is barely populated. None of this blocks production; it's the normal next layer of work.

---

## MUST-FIX (prioritized)

1. **Soften the Marrow cliff beat (`A3-10`).** Re-stage Marrow's despair away from a literal poised-to-jump / "came here to fall" tableau (suggest: surrender to the mist / giving up the will to go on) to honor the brief's "no mature themes" hard constraint. Keep the "one note" redemption intact. *(Content/sensitivity — the one true line-crossing.)*
2. **Reconcile the ship name.** "Driftwing" (ledger + script) vs "Gull's Mercy" (`02`). Pick one and propagate. *(Trivial, but it's a visible canon bug already flagged in `06`.)*
3. **Specify the `MARROW_REDEEMED` predicate in `04`.** The doc promises full determinism; this Ending-D-gating flag is left as prose. Give it an exact, testable formula. **Bundle:** rename Kestrel's squire "Pell" (`05`, CQ-KESTREL) to remove the collision with Keeper Pell.

## NICE-TO-HAVE

- Reconsider renaming **"Hollow"** to reduce the *Dark Souls* echo and sharpen the IP.
- Confirm **"magitek"/"esper"** never appear in player-facing text (currently clean — keep it that way).
- Clarify whether the **Larkfall Keel** upgrade survives the Driftwing's destruction.
- Give the **Keepers** tradition one more on-screen moment, or accept it as flavor.
- Optional: simplify one or two stretch words in dialogue (e.g., "requisitioned" → "claimed") if playtesting warrants.

---

## Closing note

This bible is well above the bar for a kids' ensemble RPG: the villains actually earn their tragedy, the theme (stewardship vs. exploitation; the world is changed by how we live together, not one magic fix) is woven into mechanics and endings rather than just stated, and the prose for players is disciplined and warm. The fixes are small and almost entirely mechanical — the lone exception being the Marrow cliff scene, which needs a gentle re-stage to live up to the brief's own promise. Make these changes and you have a story worth building.
