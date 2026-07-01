# Independent Art Critique — Wren Asset Set & Pipeline Decision

**Critic:** External reviewer (did not author any of this art).
**Standard:** `docs/art/STYLE_GUIDE.md` §7 rubric. Pass bar **≥8/10**; key art **≥9/10**. Gate question: *"Would this pass in a polished commercial indie RPG?"*
**Scope:** 5 raster refs, 1 in-scene composite, 2 rejected vector attempts, 3 rig stills.
**North-star for comparison:** `art/refs/_smoketest_meadowmoor.png` (painterly, textured, warm-focal-vs-cool-air).

Scores are per the seven rubric axes: (1) silhouette readability, (2) detail/rendering, (3) shading/light consistency, (4) palette adherence, (5) style consistency, (6) in-context legibility at game scale, (7) commercial bar.

---

## 1. Per-asset scores

### A. `art/refs/wren_v1.png` — hero portrait — **8.5/10 — PASS**
The strongest single Wren asset and the closest to a shippable hero look.
- **Strengths:** Genuinely warm, painterly, soft-defined gradient shading (no cel, no photoreal). Throat lamp-stone is present, glows amber, and correctly casts a warm halo onto the chin — the mood-light contract is honored. Warm subject against a cool blue sky-gradient background nails the §6 lighting grammar. Reads instantly as a shy, earnest child.
- **Defects:** Hair leans a **darker ochre-brown than canonical Wheat Gold `#E6C46A`** — palette drift, sample the swatch. Left eyebrow is slightly furrowed/asymmetric and the coat collar is mildly lopsided (AI asymmetry). The throat-stone is a saturated near-lightbulb yellow rather than a warmer amber *stone* — borderline but acceptable here.
- **At 128px dialogue scale:** emotion still reads. Passes.

### B. `art/refs/wren_fullbody_v1.png` — full-body — **7.5/10 — MARGINAL PASS**
- **Strengths:** Good child proportions (~1:5.5–6), clean silhouette, appealing coat/jeans/boots, grounded stance. Warm/cool logic intact.
- **Defects (real):** The throat mood-light is rendered as a **literal incandescent Edison lightbulb with a visible filament** — that is off-model. The spec calls for an amber lamp-*stone*, not a household bulb. The glow is also **blown out**, washing all detail off the shirt/chest. There's an **unmotivated full circular halo behind the head** that reads saint-like/religious — reserve glow for the throat-stone only. Face style has drifted more anime (bigger eyes, pointier chin, freckles) than the portrait.
- Passes on craft, but the bulb + blowout + halo are corrections, not polish.

### C. `art/refs/wren_apose_v1.png` — rig base A-pose — **7.5/10 — MARGINAL PASS**
- **Strengths:** Clean, near-symmetric A-pose — a sane rig source. Silhouette is closed and readable. Throat-stone reads as a small ornate amber lantern here (better than the fullbody's bulb).
- **Defects:** Face is the more generic-anime variant (see consistency note below). **Left hand fingers are mushy/webbed** — AI hand artifacting; a rig source needs clean extremities. Proportions ~1:6, slightly tall for the 1:5.5 child spec.

> **Cross-asset consistency failure (applies to A/B/C):** The three "Wren"s **do not fully look like the same character drawn by the same hand.** The portrait is a rounder, softer, Ghibli-ish painterly child; the fullbody and A-pose are a more generic large-eyed anime kid with freckles. Hair color drifts brown ↔ yellow-wheat between them. For a **character bible** this is a genuine style-consistency ding (rubric axis 5).

### D. `art/refs/meadowmoor_v1.png` — environment — **8.5/10 — PASS**
Second-strongest asset; closest to production-ready.
- **Strengths:** Faithfully hits the smoke-test: floating island, stone lamp-tower with a warm haloed lamp at the crown, grass cap, rocky rounded underside, soft cumulus, correct sky gradient. Bonus storytelling: **thin-blue fading-aether wisps at the dimming edges** — exactly the §2.2/§6 "the lamp is failing" signal. Windmills + sheep present.
- **Defects:** Renders **flatter / more mobile-casual (Rovio-ish)** than the richer painterly smoke-test — arguably fine (and better for vectorizing) but it is a slight north-star drift toward "generic casual mobile." Sheep are tiny blobs. Reads a touch generic.

### E. `art/refs/crane_v1.png` — enemy (Sleepless Crane Hollow) — **5.5/10 — FAIL**
Competently rendered, badly off-brief on the single most important thing.
- **The clever bit:** The neck as a brass articulated dock-crane arm is a genuinely good double-meaning of "crane." Ash motes fall from the beak (correct, minor).
- **Why it FAILS (§2.6 Hollow spec):** It reads as an intact, quirky **steampunk bird**, NOT an eerie-sad **Hollow**. There is **no cold pale-blue rim-light tracing a near-empty silhouette; no dim mournful grey-blue heart-core flicker; no sense that the color has *left*.** The brass neck is fully healthy saturated brass — directly contradicts "drained of aether." The eye is a plain dark bead, not a sorrowful ember core. Emotion delivered is "curious/whimsical," but the brief demands "pitiable/drained/breathless." Composition is also empty and floaty.
- This is the clearest brief failure in the set. Craft ~7; brief-adherence ~4; net FAIL.

### F. `art/_render/scene_mockup_wren_meadowmoor.png` — in-scene composite — **5/10 — FAIL**
- **What works:** The rembg cutout is reasonably clean, and Wren's warm glow is consistent with the scene's warm/cool logic. The cutout-on-background *pipeline step* is demonstrated.
- **Why it FAILS (rubric axis 6, the whole point of this test):** **Scale is broken** — Wren is rendered *taller than the entire skyland*, including the lamp-tower behind her. She looks like a giant looming over a toy island, not a hero standing on the playfield. A field sprite should be ~256px and **grounded on the terrain**. She is **not grounded**: no contact/ambient shadow, feet at the frame edge while the island floats mid-frame behind her — she reads as pasted, not placed. As a shippable frame this fails; as a proof-of-cutout it half-succeeds.

### G. Rig stills

**`art/_render/wren_rig_neutral.png` — 7.5/10 — MARGINAL PASS.** At rest the rigid part-cuts are largely hidden; only a faint tonal break at the shoulders. This is fine as a neutral/idle base.

**`art/_render/wren_wave_up.png` — 6/10 — MARGINAL / FAIL AT BAR.** The wave pose reads clearly (gesture/emote capability proven). But the **rigid rectangular shoulder cut is visible** on the raised arm — the upper-arm part rotates about its pivot and leaves a slightly detached/mismatched shoulder joint, exactly the warned artifact. Below the 8 bar as-is.

**`art/_render/wren_walk_midstep.png` — 4.5/10 — FAIL.** This is where the rigid cuts break down. There are **visible rectangular seams/ghost boxes at the hips and mid-thigh**, the thighs overlap with a hard straight-edged discontinuity, and the coat hem does not deform with the legs. It proves the walk *cycle* works, but the frame itself is not shippable.

---

## 2. Vector vs Raster verdict

### `art/_render/wren_traced_512.png` — auto-traced SVG — **5/10 — FAIL**
Passable as a cheap flat cartoon, but it destroys the north-star. The soft-defined painterly gradients collapse into **flat banded/posterized blobs**; edges are **wobbly/lumpy trace artifacts**; there are stray traced "cloud" shapes in the top corners; and the throat-stone glow/halo is **gone** (a flat yellow blob). Palette drifts (hair too orange, background a flat plate). Reads as mediocre flat-color clip-art, not "warm storybook painterly."

### `art/_render/wren_portrait_512.png` — hand-authored SVG — **3/10 — HARD FAIL**
Worse. Gradient-mesh smoothness but the **face is uncanny and broken**: features float, the nose is a smudge, eyes are asymmetric and mis-placed, the hair is a flat gradient helmet with a **stray floating blue ellipse** behind the head (the halo became an artifact), and the shoulders are a shapeless gradient blob with no coat structure. This is the amateur-vector-avatar look. It demonstrates that hand-authoring this painterly style in SVG is not achievable at sane effort.

### Verdict
**Raster wins decisively for this style.** Both vector outputs fall far below the ≥8 bar (5 and 3). The painterly, soft-gradient, warm-glow storybook look the guide demands does not survive vectorization — either the trace flattens it into cheap cartoon, or hand-authoring produces uncanny clip-art. **Vector should be retained only for UI/HUD/icons** (crisp geometry, §5.4), exactly as Pipeline A already scopes it. Vector as the *shipped character/environment/enemy* path is not viable.

---

## 3. Rig / animation assessment

**Is the capability proven? YES.** One raster source art was successfully cut, rigged, and posed into neutral, walk, and wave clips. The pipeline (Flux → cutout → Skeleton2D → reusable clips) demonstrably produces articulated frames and a walk cycle. That is the important R&D win.

**Does the rigid-cut rig pass as-is? NO.** The known rectangular-cut artifacts are **visibly failing at rest scale already**:
- Walk (4.5) shows hip/thigh seams and ghost boxes, non-deforming coat hem — not shippable.
- Wave (6) shows a shoulder-joint seam on the raised arm.
- Neutral (7.5) is the only one that holds, because nothing rotates far.

These will only worsen at portrait/zoom scale. **Mesh-deform + skin weights + cleaned masks are mandatory before ship** — this confirms the studio's own production plan. The rig is a proven *prototype*, not a shippable rig.

---

## 4. Recommendation (the automated call)

# OVERALL VERDICT: **LOCK RASTER PIPELINE (Pipeline A).**
Vector is rejected for hero/environment/enemy art and retained **UI-only**. The raster look clears the commercial bar (portrait 8.5, environment 8.5); the remaining failures are fixable brief/compositing/rig issues, not a style dead-end. This does **not** need more R&D at the *pipeline* level — it needs the MUST-FIX list closed at the *asset* level.

### Required per-asset gates (enforce automatically before an asset advances)
1. **≥8/10 on all seven rubric axes** for every hero/field/enemy/environment asset; **key art ≥9**.
2. **Black-silhouette test** must pass.
3. **Palette HEX-sampled**, not eyeballed — reject on off-swatch hair/eyes/accents.
4. **Single locked face + hair-color model** for each character — reject drift.
5. **Mood-lights present and correct** (Wren's throat = amber lamp-*stone* with the aether-glow stack; never a household bulb; no unmotivated body halo).
6. **Cutout clean** (no fringe) AND **placed to scale + grounded with contact shadow** before any in-scene shot passes.
7. **Rig clip seam-check at 2× zoom** — no visible part seams; requires mesh-deform before a clip passes.

### MUST-FIX (prioritized) before this style/rig is production-ready
1. **Crane enemy — regenerate to the Hollow spec (§2.6).** Highest priority. Needs a dark near-empty silhouette, cold pale-blue rim-light, a dim mournful grey-blue heart-core flicker, and drained/desaturated brass. Currently an intact quirky steampunk bird, not eerie-sad. Off-brief FAIL.
2. **Lock ONE Wren face + hair-color model.** Portrait (soft painterly) vs fullbody/A-pose (generic anime + freckles) are different characters; hair drifts brown↔wheat. Build a model sheet and enforce.
3. **Fix the throat mood-light token.** Replace the literal Edison bulb (fullbody) with an amber lamp-*stone* using the aether-glow stack; tame the blown-out chest glow; delete the saint-halo behind the head.
4. **Implement mesh-deform + skin weights + cleaned masks on the rig.** Rigid cuts fail (walk seams, wave shoulder seam). Not shippable until done.
5. **Fix scene compositing rules.** Establish sprite-to-environment scale (Wren must stand *on* the island at field scale, not dwarf it) and a mandatory contact-shadow/grounding pass. Current mockup fails scale + grounding.
6. **Palette discipline pass.** Sample canonical HEX; pull hair onto Wheat Gold `#E6C46A`, verify eyes/coat/accents.
7. **Minor cleanups.** A-pose left-hand finger mush; portrait collar/eyebrow asymmetry; keep meadowmoor from drifting toward generic-mobile-flat (nudge back toward the painterly smoke-test).

---
*End critique.*
