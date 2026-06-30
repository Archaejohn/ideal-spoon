# Phase 2 — Owner Rulings on Architect Open Questions

Recorded by the Owner on 2026-06-30, resolving the six items the Architect flagged. These are binding for implementation.

1. **ATB mode:** Default to **"wait" mode** — the ATB gauges pause while a party member's action menu is open (kid-friendly, forgiving on low-end devices). Provide **"active" mode** and a **decision-window timer** length as **Settings** options. (Confirms ADR-0004.)
2. **Battle resume granularity:** The **pre-battle checkpoint is the unit of resume**; mid-battle state is intentionally not persisted. A kill/quit mid-fight resumes from just before the fight — consistent with the lose-a-battle rule. (Confirms ADR-0005 §c.)
3. **Web/Chromebook durability:** The explicit **FS-sync flush after every web write is a hard requirement**, not best-effort. The web/Chromebook build is not "done" until the smoke test proves a write survives tab-hide/close/reload. (Confirms ADR-0005 §e; tracked in DoD #13.)
4. **Autosave debounce (~3s):** Accepted. Lifecycle events (pause/focus-out/back/close) bypass debounce and write immediately, so locking the phone saves at once; only a hard power-kill during plain overworld walking can lose a few seconds, never a beat/battle/menu/lifecycle transition. (Confirms ADR-0005 §a.)
5. **Resolver/story coupling:** Keep the **golden exhaustive `resolveEnding` test** pinned to `docs/story/04_BRANCHES_ENDINGS.md`. Any future change to endings must update `04`, the resolver, and the golden test together. (Confirms ADR-0009.)
6. **Crossroads scope:** After first completion, the Crossroads selector **surfaces all four endings**. For endings whose gate the player satisfied during their run, resume **faithfully** from that run's `A4-06` snapshot; for endings they never gated, **synthesize a valid canonical state** so the player can still experience it. This fulfills the Owner's intent that players can "play **any** ending." (Confirms/extends ADR-0006.)
