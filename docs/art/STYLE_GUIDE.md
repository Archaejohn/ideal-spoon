# Visual Style Guide — "Aetherbound"

> **This is the binding art bible.** Every concept reference, every authored SVG asset, every UI screen, and every AI generation must obey this document. It is built on `docs/story/00_BRIEF.md`, `docs/story/01_WORLD.md` (esp. §8 "Visual & Musical Hooks"), and `docs/story/02_CHARACTERS.md`. The north-star target is `art/refs/_smoketest_meadowmoor.png`.
>
> **Pipeline reminder (read this first).** Shipped art is **original authored SVG (vector)**, rasterized by Godot for phone/Chromebook DPIs. AI (Flux.2 Klein via `tools/art/comfy_gen.py`) generates **concept/reference images only**; artists author layered SVG from those refs. Therefore every choice in this guide serves two masters: **(a) beautiful as a painterly target, and (b) cleanly vectorizable** — clear silhouettes, readable shape hierarchy, limited cohesive palettes, soft-but-defined shading, and no photographic noise, clutter, or fussy texture that a vector artist cannot reproduce in a sane number of paths.

---

## 1. North-star & mood

**Visual thesis.** *Aetherbound* looks like a **warm storybook brought to life** — painterly, hand-illustrated, wondrous, and gently melancholy. Forms are clean and rounded, lit by soft gradients; the world reads instantly even at thumbnail size. The emotional engine is **light against the coming dark**: warm golden aether and lamp-glow stand out against a vast, cool, drifting sky. Hope is literally rendered as light — a single small lamp lit while the grey creeps in at the edges. We aim for the feeling of a beloved 16-bit ensemble RPG reimagined as a glowing children's-book painting: bright, kind, full of air and wonder, with real sadness held tenderly underneath. **Never** grimdark, never photoreal, never noisy. The smoke-test (`_smoketest_meadowmoor.png`) is the law: soft sky gradient, clean grass and stone silhouettes, a haloed warm lamp, gentle ambient shadow, no clutter. Match that warmth, clarity, and glow on every asset.

**Three words to check every asset against:** *Warm. Wondrous. Readable.*

---

## 2. Palette

All colors are authored as flat fills + gradient stops. Keep each asset to a **limited cohesive set** (a core trio plus one or two accents). HEX values are canonical — sample these, do not eyeball.

### 2.1 Core sky & atmosphere (the world's bed)

| Name | HEX | Use |
|---|---|---|
| Sky High | `#7FC4E8` | Top of the sky gradient (zenith) |
| Sky Mid | `#A9DCF2` | Mid sky, the dominant "air" tone (matches smoke-test) |
| Sky Pale | `#D6EEF9` | Horizon haze, lightest sky |
| Cloud White | `#F3FAFD` | Cloud highlights |
| Cloud Shadow | `#C2DCEC` | Cloud undersides, soft cool shadow |
| Mist Silver | `#B8C2CC` | The Underland mist sea below; cool, soundless |

### 2.2 The Aether life-cycle (the most important palette in the game)

Aether tells the story through color. Healthy → anxious → dead. Use this ramp everywhere aether appears (lamps, keels, wellstones, the Song, Resonant FX).

| Name | HEX | Stage |
|---|---|---|
| Aether Gold Core | `#FFE9A8` | Healthy glow center (near-white hot) |
| Aether Gold | `#FFC64B` | **Healthy aether** — full strength, warm and alive |
| Aether Amber | `#F2922B` | Healthy aether, deep edge / lamp body warmth |
| Aether Thin-Blue | `#8FB7D6` | **Anxious / failing** aether — running low, cooling |
| Aether Pale-Blue | `#BFD4E2` | Guttering, almost spent |
| Aether Grey | `#9AA2A8` | **Dead aether** — the Fading; color drained out |
| Aether Ash | `#6E747A` | Fully dead, the Long Quiet |

> **Rule:** an object's aether glow shifts **gold → thin-blue → grey** to communicate health. Designers use this as a gameplay-readable signal (a player learns "blue lamp = in trouble, grey lamp = dead"). Never use red/green for danger — danger is *cold and colorless*, not hostile.

### 2.3 Warm lamp-light vs cool sky (the lighting contract)

| Name | HEX | Use |
|---|---|---|
| Lamp Glow Halo | `#FFD56A` @ low alpha | The soft radial halo around any warm light source |
| Lamp Light Warm | `#FFEFC2` | Lit interiors, warm rim-light on characters near a lamp |
| Warm Shadow | `#6B4E3D` | Shadow tone for warmly-lit objects (never pure black) |
| Cool Shadow | `#3E5A73` | Shadow tone for sky-lit / cool objects |
| Ambient Occlusion | `#2E2A34` @ low alpha | Soft contact shadow under objects (see smoke-test island base) |

> **Rule:** warm and cool are in constant dialogue. Lit side = warm; shadow side = cool. Shadows are **tinted**, never neutral black.

### 2.4 Skin & material neutrals

| Name | HEX | Use |
|---|---|---|
| Skin Light | `#F4D2B0` | Fair skin base |
| Skin Mid | `#D9A878` | Medium skin base |
| Skin Deep | `#9A6B47` | Deep skin base |
| Skin Shadow Tint | `#B07A57` | Shared warm shadow multiply over skin |
| Stone Warm | `#CDB48C` | Skyborn sandstone, lamp-towers (smoke-test stone) |
| Stone Shadow | `#9A8260` | Stone shadow |
| Grass Light | `#A6D24E` | Sunlit grass top |
| Grass Mid | `#6FA834` | Grass body |
| Grass Shadow | `#3F7027` | Grass shadow / island edge |
| Earth Dark | `#4A3B33` | Island underside rock |
| Brass | `#C8923E` | Skyborn relic metal, Tam's gear, Bramble |
| Brass Shadow | `#8A5E26` | Brass shadow |
| Canvas/Sailcloth | `#E4D5B7` | Coats, sails, Wren's coat |
| Wood Warm | `#A6763F` | Skyship hulls, beams |

### 2.5 Faction & character accent palettes

Each faction/character owns a recognizable accent. Keep accents **few and saturated against the neutral world**.

| Faction / Subject | Accent Name | HEX | Notes |
|---|---|---|---|
| **The Ascendancy** | Imperial Slate | `#4A5560` | Cold, severe, orderly |
| | Ascendancy Iron | `#2F363D` | Armor deep tone |
| | Mourning White | `#EDEFF2` | Single trim line; Thane's grief |
| **The Lantern Order** | Prayer Blue | `#2E5A8C` | Mira's sash, deep faith-blue |
| | Candle Cream | `#F6ECCF` | Robes, candle-boats |
| | Order Gold | `#E8B24A` | The ever-lit lantern flame |
| **Keepers (Wren's craft)** | Wheat Gold | `#E6C46A` | Wren's signature warmth |
| | Lamp Amber | `#F2922B` | Her throat-stone, her glow |
| **Free Sky-folk / Salvagers** | Storm Grey | `#5B636B` | Sable's coat base |
| | Salvage Brass | `#C8923E` | Spyglass, relics |
| | Patchwork (multi) | faded `#B7A77E`/`#8C9C8E`/`#A66E5A` | Sable's mismatched-sailcloth coat |
| **Kestrel (defector)** | Falcon Russet | `#9A4E2E` | The warm color bleeding back through scraped slate |
| **Verdance** | Jungle Deep | `#2F6B4F` | Overgrown green |
| | Glow Pollen | `#CFE87A` | Singing-flower shimmer |
| **The Glasswastes** | Glass White | `#EAF1F4` | Fused sand, mirror-shard scatter |
| | Mirror Cyan | `#9FD3DA` | Light-scatter glints |

### 2.6 The Hollow (cold-rimmed absences)

The Hollow are **eerie-sad, not scary-violent**. They read as silhouettes that the color has *left* — a shape of cold rim-light around an ashen, near-empty interior. Never bloody, never fanged-monster. The scare is *absence*, the emotion is *pity*.

| Name | HEX | Use |
|---|---|---|
| Hollow Void | `#262A30` | The empty interior (very dark, slightly desaturated, never pure `#000`) |
| Hollow Rim | `#A9C6D6` @ glow | The faint **cold** rim-light tracing the silhouette |
| Hollow Static | `#7E8890` | Ash-and-static flecks drifting off the form (sparse, soft) |
| Hollow Ember | `#5A6470` | Dim, mournful core-flicker where a heart-stone used to be |

> **Rule:** a Hollow is built as *dark shape + cool rim + a sad dim core*. Their motion drifts. They lean *toward* warm light (they're hungry for it). Keep them gentle: rounded, slow, sorrowful — a hollowed crane, a faded garden-tender, never a gore-creature.

---

## 3. Line, shading & rendering

**Pick-one cohesive approach:** **soft-painterly with a controlled clean edge** — *not* hard cel-shading, *not* photoreal rendering. This is the smoke-test look and it vectorizes well as **layered gradient fills with crisp silhouette edges**.

- **Line.** No heavy black ink outlines. Forms are defined by **shape and value**, with an optional **darker-tone self-colored contour** (a deeper shade of the fill, never pure black) used sparingly to separate overlapping forms. Where a contour is used, keep weight **even and confident**; thin it at highlights, thicken slightly in shadow. Silhouette edges stay **clean and closed** so the vector artist gets one solid path.
- **Shading model.** **Two-to-three-stop soft gradients per form**: base → shadow → (optional) core-shadow, plus one highlight. Transitions are *soft but defined* — a readable gradient band, not a fuzzy airbrush haze and not a hard cel step. Think "rounded volumes lit by a soft sun." Each form should be reproducible with **≤4 gradient stops** so SVG stays light.
- **Highlights.** One primary highlight per form, warm-tinted (`Lamp Light Warm`) on the lit side. Add a **cool rim-light** (`Sky Pale`/`Cool Shadow`) on the shadow-side edge to pop characters off the sky. Keep speculars soft and few; no glossy plastic hotspots.
- **Shadows.** Tinted, never black (see §2.3). Contact/ambient shadow under every grounded object as a soft low-alpha ellipse (see the island base in the smoke-test).
- **Aether glow rendering.** Built in layers, all vectorizable: (1) a **radial gradient halo** (`Lamp Glow Halo`, transparent at the rim), (2) a **hot core** (`Aether Gold Core`), (3) **warm rim-light cast onto nearby surfaces**. The halo's *color* carries health (gold/blue/grey per §2.2) and its *radius/opacity* carries strength. No lens-flare spikes, no noise.
- **Depth & atmosphere.** Use **atmospheric perspective**: distant skylands shift toward `Sky Pale`, lose contrast, and soften. Foreground keeps full saturation and crispest edges. Layer in **2–4 depth planes** (hero → mid → far → sky) with gentle parallax-friendly separation. Everything drifts gently; nothing is locked rigid.

---

## 4. Proportions & character design language

**Friendly-but-not-chibi storybook realism.** Heroes are appealing and rounded, with clear age reading — never super-deformed bobbleheads, never gritty-realistic.

- **Head:body ratios.**
  - **Child heroes (Wren, Tam — age 14):** ~**1:5.5** (heads tall). Slightly larger heads and eyes than adult-realistic for warmth and youth, but clearly children, not toddlers.
  - **Teen/young adult (Mira, 19):** ~**1:6**.
  - **Adults (Sable 38, Kestrel 27):** ~**1:6.5–7**. Capable, grounded.
  - **Elder (Rookwise 71):** ~**1:6.5**, stooped — silhouette curves into a question-mark.
- **Silhouette rules (the single most important design test).** Every character must be **identifiable as a pure black silhouette**. Each owns one strong shape-signature: Wren = *a child cupping a flame* (slight, hunched, oversized coat); Sable = *coat-tails snapping, hands in pockets, deck-lean*; Tam = *a kid mid-gesture with tools jutting at every angle*; Mira = *serene upright, lantern held forward*; Kestrel = *knight at attention, blade grounded*; Bramble = *a tiny round wanderer, head tilted*; Piggy = *a fuzzy upright egg with a tilted-up beak*. Avoid silhouette-merging clutter (no tiny dangly bits that blur the outline at game scale).
- **Faces.** Soft, rounded, expressive. Eyes large enough to read emotion at portrait scale but not anime-huge. Simple, warm features; avoid wrinkled detail except as a few clean lines on elders.
- **Signature mood-lights.** Two characters carry a **mood-light** the art must treat as a live element: **Wren's throat lamp-stone** (brightens when she's afraid; render with the aether-glow stack) and **Piggy's fluff-crown** (rises when proud, droops when sad). These are canonical and always rendered.
- **How Resonants / aether read visually.** A Resonant in the act of Listening/Shaping is haloed in **soft gold Song-light**, with faint concentric ripple-rings (clean vector arcs, low alpha) emanating from the chest/hands and **musical-shimmer motes** (sparse). The Song is *warm, gentle, golden* — never an aggressive energy-blast. Near the Fading the same FX thins to **Aether Thin-Blue** and falters; in dead zones it nearly vanishes (the visual scare = the light *leaving*).
- **The mascot Piggy.** A **fluffy dove-grey baby emperor penguin**, round and downy, two enormous ink-drop eyes, stubby flippers, bolt-upright royal posture (flippers clasped behind back). The fluff-crown and the frayed **Skyborn-gold sash** are mandatory. He reads as *majesty in miniature* — cute, brave, trying hard. Palette: `#C9CDD2` dove-grey body, `#F3F6F8` downy white face/belly, one thread of `#E8B24A` Skyborn-gold in the sash. Keep him **adorable, never grotesque**.
- **Bramble.** Small (knee-to-waist on humans), **rounded and gentle, not menacing**: warm relic-brass + pale ceramic, big lamp-lit optic-eyes that tilt, a chest-stone behind a grille that pulses like a heartbeat (aether-glow stack), real moss grown into the joints (`Glow Pollen`/`Jungle Deep` greens). Reads as a clockwork child, the world's living conscience.

---

## 5. Per-asset-class specs

> **Authoring note for all classes:** design at the listed SVG artboard size; Godot imports the SVG and rasterizes at multiple scales. Keep the **paths few and the palette limited**. Provide a clean transparent background unless it's an environment/key-art piece. Anchor/pivot conventions below are for the rasterized texture as placed in Godot.

### 5.1 Character full-body (party & NPCs)
- **Purpose.** Overworld/field sprite source, party menu, combat actor.
- **Detail level.** Medium-high. Full silhouette clarity, signature props legible, 3-stop shading.
- **Artboard.** **1024×1536** SVG (portrait), character ~85% of frame height, centered horizontally.
- **Anchor/pivot.** **Bottom-center** (feet), for ground-snapping in Godot.
- **"Done" =** passes the black-silhouette test; reads cleanly when rasterized to ~256px tall (field scale); warm/cool light consistent; ≤~6 fills per major region; mood-lights present where applicable.

### 5.2 Enemy / Hollow
- **Purpose.** Combat opponent.
- **Detail level.** Medium. **Silhouette + cold rim + sad dim core** for Hollow; clean readable shapes for Tinplate/constructs.
- **Artboard.** **1024×1024** (or 1024×1536 for tall enemies like the Crane). Subject ~80% of frame.
- **Anchor/pivot.** Bottom-center (grounded) or true-center (floating/drifting Hollow).
- **"Done" =** eerie-sad not gory; instantly reads as "drained/hollow" via the §2.6 palette; legible at combat scale; no horror/gore content.

### 5.3 Environment / skyland
- **Purpose.** Establishing shots, battle backgrounds, location concept.
- **Detail level.** High on hero element, soft/atmospheric on distance. 2–4 depth planes.
- **Artboard.** **1920×1080** (16:9) SVG, safe-area aware (Chromebook + phone letterboxing).
- **Anchor/pivot.** Full-frame; mark a clear focal point and horizon line.
- **"Done" =** matches the smoke-test sky gradient + soft clouds + clean island silhouette; atmospheric depth reads; warm focal light vs cool air; uncluttered enough that the SVG layers are sane (background sky, cloud band, far islands, mid terrain, hero element, FX/glow).

### 5.4 UI / HUD
- **Purpose.** Menus, battle HUD, dialogue boxes, buttons, icons.
- **Detail level.** Crisp, minimal, **high contrast for legibility** on small Android screens. Rounded warm-storybook frames (lamp-brass + canvas vibe), gold accents from §2.5.
- **Artboard.** Icons **128×128**; panels authored at **1× = 1920×1080 reference grid**, all elements on a 8px grid.
- **Anchor/pivot.** Per-element nine-slice for panels; icons centered.
- **"Done" =** readable at the smallest target DPI; uses aether-ramp colors for status (gold=good, thin-blue=low, grey=depleted); never competes with the art for attention; touch targets ≥ 48px on phone.

### 5.5 Portrait
- **Purpose.** Dialogue headshots, party select, recruitment cards.
- **Detail level.** High on face, simple framing. Warm rim-light, expressive but clean features.
- **Artboard.** **768×768** SVG, head-and-shoulders, face in upper-center third.
- **Anchor/pivot.** Center; consistent eye-line across the cast (place eyes at ~38% from top) so portraits cut together.
- **"Done" =** character instantly recognizable; emotion legible at the ~128px dialogue scale; lighting consistent with the scene's warm/cool logic; signature detail visible (Wren's throat-stone, Mira's lantern, etc.).

### 5.6 Key art
- **Purpose.** Title screen, store/marketing, chapter splashes.
- **Detail level.** Highest. Full painterly composition, dramatic light, emotional staging.
- **Artboard.** **2560×1440** SVG, composed for safe-area crops down to phone.
- **Anchor/pivot.** Full-frame, rule-of-thirds focal, room for logo (upper or lower third).
- **"Done" =** hits the thesis in one image (warm light against cool vast sky, hope as a small flame); commercial-indie quality; passes the §7 critic rubric at **≥9/10**.

---

## 6. Lighting model

The world runs on **one rule: warm light against cool dark.**

- **Default day.** A soft, high, slightly-diffused sun. Sky is the cool bed (`Sky Mid`); every *living* thing (lamps, keels, charged wellstones, Resonant Song, hearths) is a **warm point of light** that casts gold rim-light onto nearby surfaces and a soft halo into the air. The contrast of *warm small light vs cool vast air* is the emotional grammar of every frame.
- **The Fading (aether dying).** Color **desaturates toward grey from the edges inward.** An ailing island keeps a warm lit heart but its rim drains to `Aether Thin-Blue` then `Aether Grey`; saturation drops, contrast flattens, the warm halos shrink. This is a *gradient of loss* the player reads at a glance. Post-Second-Sundering (Act III) the whole palette sits cooler and greyer, with warm light now precious and rare.
- **Hollow zones.** Go **cold and "tuneless."** Warm light is nearly gone; the dominant tones are `Hollow Void`, `Mist Silver`, `Cool Shadow`. The only lights are the **cold rims** of the Hollow themselves. Visually it should feel like *the sound has left the picture* — still, desaturated, breathless. Not dark-scary-violent; *empty-sad.*
- **The highs (celebration scenes).** Crank the warm: the Relighting festival, a town relit, the getaway — flood the frame with golden lamp-glow, floating lanterns, full saturation, the Song-light *soaring*. These warm peaks exist so the grey lows cut deep. Let joy be loud and golden.
- **The descent to the Wellspring (Act IV).** The world "holds its breath": deep mist-dark below, building toward the Warden's **cathedral-at-dawn** golden light — awesome, gentle, never monstrous.

---

## 7. Cohesion rules & the critic rubric

**Cohesion rules (non-negotiable):**
1. Every asset uses the **canonical HEX palette** (§2). No off-model colors.
2. Every asset uses the **soft-painterly + clean-silhouette** rendering (§3). No hard cel, no photoreal, no heavy black ink.
3. **Warm-light-against-cool-dark** lighting logic holds in every frame (§6).
4. **Silhouette test** passes for every character/enemy (§4).
5. Aether health is always communicated by the **gold → thin-blue → grey** ramp (§2.2).
6. Age-appropriate always: **no gore, no mature themes**; Hollow are *eerie-sad*, villains *tragic*, death shown as *fading to light*.
7. Everything must **vectorize cleanly** — limited palette, ≤~4 gradient stops per form, closed clean silhouettes, no noise/clutter.

**The Art Quality Loop — critic rubric (target: ≥ 8/10 to pass; key art ≥ 9).** Score each generated reference and each authored asset on:
1. **Silhouette readability** — clear, identifiable as a black shape?
2. **Detail & rendering quality** — confident painterly forms, no mush, no AI artifacting?
3. **Shading & light consistency** — soft-defined gradients, tinted shadows, correct warm/cool?
4. **Palette adherence** — on the canonical HEX swatches?
5. **Style consistency** — matches the smoke-test north star and the rest of the set?
6. **In-context legibility at game scale** — does it still read when rasterized to its real in-game size (field sprite ~256px, portrait ~128px, icon ~48–128px)?
7. **Commercial bar** — *"Would this pass in a polished commercial indie RPG?"*

If any axis scores low, regenerate/revise before the asset advances to SVG authoring or ships.

---

## 8. Reference-generation prompt recipe (Flux.2 Klein / `tools/art/comfy_gen.py`)

### 8.1 BASE STYLE PROMPT fragment (the cohesion anchor — append to EVERY generation)

```
warm storybook painterly illustration, hand-painted children's-book fantasy concept art, soft defined gradient shading with clean closed silhouettes, rounded appealing forms, limited cohesive palette, warm golden lamp-light glowing against a cool soft-gradient sky, tinted soft shadows (never pure black), gentle atmospheric depth, clear readable shape hierarchy optimized for vector tracing, wondrous and gently melancholy mood, soft ambient glow, no harsh detail, cohesive indie RPG art direction
```

### 8.2 NEGATIVE prompt (use on EVERY generation)

```
photorealistic, photograph, 3d render, harsh noise, grain, film grain, busy cluttered background, excessive fine detail, hard black ink outlines, heavy cel-shading, lens flare, text, watermark, signature, logo, ui, frame, border, gore, blood, wound, scary horror, violence, weapons aimed at viewer, mature content, suggestive, creepy realistic faces, distorted anatomy, extra limbs, extra fingers, muddy colors, oversaturated neon, glitch, low contrast mush, jpeg artifacts
```

### 8.3 Recommended size & steps per asset class (Flux.2 Klein)

| Asset class | Size | Steps | CFG/Guidance | Notes |
|---|---|---|---|---|
| Character full-body | 832×1216 | 28–32 | ~3.5 | Portrait; upscale later if authoring needs it |
| Portrait | 1024×1024 | 28–30 | ~3.5 | Head-and-shoulders |
| Enemy / Hollow | 1024×1024 (832×1216 if tall) | 28–32 | ~3.5 | |
| Environment / skyland | 1344×768 | 30–36 | ~3.0 | 16:9 establishing |
| Key art | 1344×768 (then upscale) | 36–40 | ~3.0 | Highest effort |
| UI / icon | 1024×1024 | 24–28 | ~3.5 | Generate motifs, then author crisp |

### 8.4 The first reference set — three ready-to-run prompts

Each = subject description **+** the BASE STYLE fragment (§8.1). Run with the NEGATIVE prompt (§8.2).

---

**(A) WREN — hero portrait** · *size 1024×1024, steps 30*

```
Hero portrait of Wren, a slight timid 14-year-old girl, a secret lamp-keeper, head and shoulders, gentle earnest expression mid-listen as if hearing distant music, soft brown wheat-gold hair escaping its tie, wearing a patched oversized canvas coat two sizes too big with deep pockets, a small glowing amber lamp-stone on a leather cord at her throat casting a soft warm halo on her chin, warm wheat-gold and lamp-amber tones on her against a cool soft-blue sky background, friendly storybook child proportions large warm eyes not chibi, warm rim-light on one side cool rim-light on the other, --- warm storybook painterly illustration, hand-painted children's-book fantasy concept art, soft defined gradient shading with clean closed silhouettes, rounded appealing forms, limited cohesive palette, warm golden lamp-light glowing against a cool soft-gradient sky, tinted soft shadows (never pure black), gentle atmospheric depth, clear readable shape hierarchy optimized for vector tracing, wondrous and gently melancholy mood, soft ambient glow, no harsh detail, cohesive indie RPG art direction
```

---

**(B) MEADOWMOOR — environment / skyland establishing shot** · *size 1344×768, steps 34*

```
Establishing shot of Meadowmoor, a small green farming skyland floating in a bright endless sky, gentle rolling grass meadow on a chunk of stone and earth with a softly rounded underside hanging in open air, a few rustic windmills and tethered sheep, one weathered stone lamp-tower at its heart with a warm golden glowing lamp at the top haloed in soft light, faint thin-blue cool wisps of fading aether drifting at the dimming edges of the island hinting the lamp is failing, soft cumulus clouds, atmospheric distant skylands fading to pale blue on the horizon, warm focal light against cool vast air, peaceful sleepy beloved mood with a touch of melancholy, --- warm storybook painterly illustration, hand-painted children's-book fantasy concept art, soft defined gradient shading with clean closed silhouettes, rounded appealing forms, limited cohesive palette, warm golden lamp-light glowing against a cool soft-gradient sky, tinted soft shadows (never pure black), gentle atmospheric depth, clear readable shape hierarchy optimized for vector tracing, wondrous and gently melancholy mood, soft ambient glow, no harsh detail, cohesive indie RPG art direction
```

---

**(C) THE SLEEPLESS CRANE — Act-I boss, hollowed Skyborn crane-construct** · *size 832×1216, steps 32*

```
The Sleepless Crane, an Act-one boss, a large hollowed Skyborn dock-crane construct shaped like an elegant long-necked mechanical crane bird made of aged brass and pale ceramic, once a gentle helper now drained of aether and stirred into a Hollow, its form is a dark near-empty silhouette traced by a faint cold pale-blue rim-light, a dim mournful grey-blue core-flicker where its heart-stone used to glow, sparse soft ash-and-static motes drifting off it, drooping sorrowful posture leaning toward distant warm light as if hungry for it, eerie and sad rather than violent, standing on a dim greying skyland edge under a cool pale sky, gentle and pitiable not gory not scary, age-appropriate, --- warm storybook painterly illustration, hand-painted children's-book fantasy concept art, soft defined gradient shading with clean closed silhouettes, rounded appealing forms, limited cohesive palette, warm golden lamp-light glowing against a cool soft-gradient sky, tinted soft shadows (never pure black), gentle atmospheric depth, clear readable shape hierarchy optimized for vector tracing, wondrous and gently melancholy mood, soft ambient glow, no harsh detail, cohesive indie RPG art direction
```

---

*End of Style Guide. This document governs `art/refs/` generation and all authored SVG. Update only with Art Director sign-off; flag any change that contradicts `00_BRIEF.md`.*
