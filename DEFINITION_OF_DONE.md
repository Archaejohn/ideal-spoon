# Definition of Done

The game is **complete** only when every item below is true. If any item is false, the game is not complete — keep working.

1. **Shell & flow** — Title screen, New Game, Continue, Settings, Credits all functional. Saving is **automatic** (no manual save slots required); "Continue" resumes exactly where the player left off.
2. **Main story** — Complete main storyline playable start to finish, with at least multiple diverging/merging paths and multiple distinct endings.
3. **Side content** — A meaningful set of side quests beyond the main line.
4. **Battle** — FF-style ATB battle system: parties, enemies, abilities, items, status effects, leveling, balanced encounters, and win/lose handling.
5. **Art** — Original, detailed art for all characters, enemies, environments, and UI. No placeholder primitives in the shipped build. Every asset has passed the Art Quality Loop (independent critic score ≥ 8/10 + completeness sign-off + Art Director ship call). The whole-game visual cohesion gate passes.
6. **Audio** — Cohesive original soundtrack covering all major areas/moods, plus SFX.
7. **Age-appropriateness** — All content suitable for a 10-year-old reading at a 6th-grade level. No profanity, graphic violence, or mature themes.
8. **Offline** — No network access, no telemetry, no ads. Verified offline. Runs on Android phone and Chromebook.
9. **Tests** — All logic covered by thorough, meaningful unit tests (≥80% on non-UI logic modules; tests assert behavior). Full GUT suite green.
10. **Process** — Every feature merged via branch → PR → independent review → approval. `main` is releasable.
11. **Docs** — Decisions captured as ADRs + indexed in `DECISIONS.md`.
12. **Build** — Successful Android build artifact (.aab/.apk) produced and a smoke-tested run completed; Chromebook-compatible build produced.
13. **Automatic, resilient saving (Owner requirement)** — Saving is fully automatic with **no manual action required**. The game autosaves continuously and **crash-safely**, so progress survives the phone being shut off, locked, or the app being killed/backgrounded mid-play (including by a parent). On battle start (and other risky points) the game writes a **checkpoint** so that losing a battle returns the player to just before it — never to the title or a distant point, and never restarting the whole game. Writes are atomic (no corrupted saves). Verified by: unit tests on save/load + checkpoint round-trips, and a manual kill/relaunch and lose-a-battle smoke test.
14. **Replayable endings (Owner requirement)** — After finishing the game once, the player can replay **any** ending. From a post-game selector, the player resumes from the **story-divergence point** that determines that ending and plays forward to it, without redoing the whole game. Verified by: unit tests that the selector unlocks all reached/known endings and that resuming from each divergence point reconstructs valid story-graph/flag state.

## Quality gates that block "done"
- **Definition-of-Done gate** (Architect): on any proposal to advance/finish, answer "Is the game complete per this list?" If no, keep building.
- **Art Quality Loop**: per-asset critic ≥ 8/10, completeness sign-off, Art Director ship call.
- **Visual cohesion gate**: contact sheet of all art reads as one product.
- **CI gate**: GUT suite green on every PR; no merge on red.
