# Design spec: Aftertaste (website and app)

**Why:** Aftertaste is EverydayOpen's fourth app and must read as a sibling of Whydunit ("Daylight", light, a desktop
diorama), Tirekick ("Night Bay", dark, an inspection bay) and Overstay ("Last Call", a room after the party) while having
its own world. The bar is the family's reference set (Maccy, Rectangle, VoiceInk, Recordly, Mole, MaCursor): a real
product object inside a small world with one light source, on a page that is otherwise quiet.
**Authority:** this file is authoritative for visual design (tokens, surfaces, compositions, type, icon).
`docs/MOTION.md` is authoritative for motion and is referenced by section. BUILD_PLAN (§7 screens, §8 UI rules and
copy, §9 demo) is the contract; where this file wants a BUILD_PLAN or copy change it is listed in §9, not made.
**Shared system:** §1.1 (the eight rules), §2.3–§2.7 (web foundation) and §6.1 (`surface`, `OnFloor`, `Horizon`,
`Metric`, `Tag`, `KeyCapStyle`, `HoverTilt`) are the same mechanics as the Overstay, Tirekick and Whydunit
`docs/DESIGN.md`; copy fixes to all four. Everything else here is Aftertaste's.
**Status:** nothing in this file has been built. Every contrast figure was computed with `tools/build_site.py`'s
`contrast()` formula (`<scratchpad>/aftertaste_contrast.py`, 2026-10-03). The Swift is written, not compiled, and no
Mac has run it; anything unconfirmed is marked VERIFY. Copy in this file never uses a phrase from
`tools/banned_phrases.txt`; the site and app owners keep it that way (BUILD_PLAN §3.1 check 17).

## 1. The verdict: "The Morning After" (world: the afterglow)

The theme is what lingers. The world is **a tidy desk at first light**: the sky behind it is the last of the night, a
calm afterglow that runs from violet at the top to teal at the horizon, and the horizon line is the only light in the
scene. On the desk an app has just left. Where it stood there is a faint dashed **outline**, and beneath the outline,
layered like sheets it slept on, the things it left behind: caches, settings, saved state, containers, helpers. Aftertaste
lifts those layers one by one into the Trash tray at the edge of the desk; the outline fades; a small printed card (the
Trace Report) says what was found. That one picture gives every surface its colour (violet = "left behind", the only
accent; teal only ever in the sky), its motion (the peel into the tray and the outline that fades) and its resolution
(the quiet state is a clear desk at daybreak, not a celebration).

| | Whydunit | Tirekick | Overstay | **Aftertaste** |
|---|---|---|---|---|
| Direction | Daylight (light-first) | Night Bay (dark everywhere) | Last Call (dark-first, follows the system) | **The Morning After** (dark-first, follows the system; a true light mode, "full daylight") |
| World | a macOS desktop diorama | an inspection bay | a desk at night by a lit door | **a desk at first light**: the afterglow sky, a horizon line, an outline where an app stood, the layered leftovers beneath it, a Trash tray at the desk's edge, the printed Trace Report card |
| Key light | the dawn glow | one lime laser | the door light | **the horizon**: a thin teal line where the afterglow meets the desk, with a soft pool on the desk below it |
| Accent | sky blue | hi-vis lime | amber | **dusk violet** `#A99BFF` with near-black text; as text `#5A44C4` (light) / `#B7A8FF` (dark); green only for "Nothing found" and moved rows; red only on a failed row's symbol |
| Type voice | Inter Display, centered | Inter Display, mono readouts | system display face, rounded numerals | **system display face, no webfont** (§2.2); left-aligned hero; **rounded numerals** for sizes and counts; mono for paths and bundle IDs |
| Signature object | the window on the wallpaper | the paper report card | the weight bar of slabs | **the outline** (the after-image a moved item leaves) and **the residue bar** (one proportional bar per app) in the app; **the layered slabs** and the **Trace Report card** on the site |
| Signature motion | the notification lands | the beam sweeps | the sweep to the door | **the peel**: layers lift one by one into the tray; **the fade**: the outline dissolves; the card turns over |
| Radii | 8/12/18/28, pills | 6/10/14/20 | 7/11/16/24 | **8/12/18/26**, 12px buttons: rounder than Overstay, firmer than Whydunit's pills |

**Decided, in this brand:**

1. **No webfont** (Overstay's decision 1, kept): the site budget is CSS ≤ 40 KB, JS ≤ 6 KB, no font file. Headlines
   use the system display face at 600 with tight tracking (§2.2).
2. **The site follows the system scheme** and the dark palette is designed first: it is the one on every screenshot,
   the OG image and the card. Light mode is the same desk in full daylight, not a grey page.
3. **Violet is the one accent and it means "left behind".** It is on the primary button, the lit edge of a High slab,
   the tier dot of a High chip and the outline. Teal appears only inside the afterglow gradient and the horizon line
   (sky, never UI). Green is a status (nothing found, a moved row's check). Red appears only on a failed row's symbol.
   **Tier is never conveyed by colour alone** (BUILD_PLAN §8): the chip carries the word; a Review row is set exactly
   like a High row; Hands off and Needs admin rows differ from the others only by having no checkbox and a reason.
4. **Honest objects.** The slabs are drawn like the app's own rows (class name, rounded size, a tier chip). The
   Trace Report card on the site is the app's card verbatim, sample data, with the footer sentence on its back. The
   Hands-off slab ("Launch agents · 2 · listed") never peels: the page shows the limit the app has.
5. **Two buttons, two shared JS jobs.** The hero's "Move 4 items to Trash" is a real `<button>` driving the peel
   (`data-sweep`, MOTION §2.4); "Turn the card over" is a `data-flip` button (the shared flip job). Both are
   keyboard-, tap- and click-reachable, hidden without JS, instant under Reduce Motion. `motion.js` is Overstay's file
   with the sweep's status strings read from attributes (MOTION §2.4), still under 6 KB.
6. **Glass only on the controls layer** (`barSurface()`, §6.2): the preview's selection bar with the move button and
   the result sheet's action bar. Content sits on porcelain surfaces; slabs and cards are opaque.
7. **No vendor marks, fictional apps.** The site and the demo show "Orbit Meet", "Paperplane Notes", "Lumen Player"
   (BUILD_PLAN §9); icons are neutral SF Symbols in the app and inline stroke glyphs on the site (§4.3).
8. **The word "safe" appears nowhere** on the site or in the app chrome (BUILD_PLAN §8). The guides say "rebuilt
   automatically", "may hold your data", "listed, not removed".

**Not doing:** a CDN, a tracker, any font file, a star count, autoplay video, mesh blobs, gradient text, emoji
icons, glass on content, a nav CTA that hides itself, `style=""` attributes, `data-theme`, an outline that never fades,
a broom or sparkle anywhere, a "space freed" number before the Trash is emptied, a red anything that is not a failed
row's symbol, a percentage progress bar (scans report by place), any of the banned phrases.

### 1.1 The eight rules (shared with the siblings)

1. **One world per product, and it appears only behind objects:** the hero scene, the "What it finds" media well, the
   finale and the download page's icon. Every other section is paper (light) or graphite (dark), paced by whitespace.
2. **One key light per scene.** Aftertaste's is the horizon. Nothing else glows, and a glow is never tier- or
   status-coloured (MOTION §1.1 rule 3): a Review row is lit exactly like a High row.
3. **Light, not lines.** Every raised surface has a lit top edge (`inset 0 1px 0`), a 0.5px hairline (a 1px light
   rim in dark, because black swallows shadows) and a shadow tinted with the brand's ink (violet-black), never
   neutral grey, never animated (MOTION §1.4).
4. **One accent.** Violet means "left behind" and is the only accent. Green and red mean a status and appear only in
   6px dots, symbols and tag fills behind primary text. A tier never gets a coloured panel.
5. **Objects, not illustrations.** Every product visual is a faithful Mac object: an app icon tile, a Finder-style
   row, a window, a sheet, a printed card, a Trash tray. No clouds, orbs, brooms or sparkles.
6. **Everything you can press is a key-cap:** a gradient lighter at the top, a lit rim, a hairline, a shallow side
   wall, and a press that sinks 1–2px with the shadow swapped instantly (never transitioned).
7. **Concentric radii:** outer radius = inner radius + padding. Aftertaste 8/12/18/26 and 12px buttons. Grain (≤ 6%,
   inline SVG) only on the sky gradients, never under body text.
8. **The apps stay native.** `NavigationSplitView`, `List`, sheets, the toolbar are system parts. Premium comes from
   the afterglow wash, porcelain surfaces, one lifted object per screen, the violet, the tags, the key-caps and the
   precision of the type. Nothing moves at idle.

## 2. Web foundation

### 2.1 The contract with `tools/build_site.py`

- `contrast()` reads exactly two `:root { }` blocks and only 6-digit hex tokens: light first, then
  `@media (prefers-color-scheme: dark)`. It measures `--text`, `--text-2`, `--accent` on `--bg`, `--bg-alt`,
  `--card`, and `--on-button` on `--button` and `--button-hover`. Every other override sits on `html[lang]` (§2.7),
  never on a third `:root`.
- Hero copy sits on `--bg` (the sky is behind objects only), so no new pairs are needed. The slabs, the tray and the
  card are `aria-hidden` or `role="img"` pictures with fixed colours, not measured.
- `data-theme` and `localStorage` must not appear anywhere, including comments. No `style=""` (stagger indices and
  slab depths use `:nth-child`).
- The CSP is the siblings' exact string, unchanged, in `layout.html` and the `CSP` constant:
  `default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'`.
- `BUDGET` in `build_site.py` (infra): `styles.css` 40 000, `motion.js` 6 000, `index.html` 36 000, `shots/*`
  110 000; a font file appearing under `site/static/` is itself a `--check` error.
- `--check` also greps the built pages for `tools/banned_phrases.txt` (BUILD_PLAN §3.1 check 17 covers `site/`); a
  line that must quote one (a guide saying what the app never claims) carries `no-claim-ok` in an HTML comment on
  that line and says why.

### 2.2 Type: the system display face, no webfont

```css
--font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI Variable Text", "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
--font-display: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI Variable Display", "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
--font-num: ui-rounded, "SF Pro Rounded", var(--font);
--font-mono: ui-monospace, "SF Mono", SFMono-Regular, Menlo, "Cascadia Mono", Consolas, monospace;
```

**Type ladder.** Put this comment at the top of `styles.css`; no size outside it.

```css
/* Type ladder (docs/DESIGN.md §2.2). Display = var(--font-display) 600; numerals = var(--font-num) 600 tabular;
   everything else = var(--font). No webfont: the ladder is tuned so SF Pro Display and Segoe UI Variable both hold it.
   h1       display  clamp(2.75rem, 1.5rem + 4.6vw, 5rem)     / 1.02, -.034em, text-wrap: balance
   h2       display  clamp(2rem, 1.35rem + 2.4vw, 3.125rem)   / 1.06, -.028em, balance
   feature  display  clamp(1.5rem, 1.2rem + 1vw, 2rem)        / 1.12, -.022em
   card h3  system   17px / 1.3, -.015em, 600
   lede     system   clamp(1.125rem, 1rem + .45vw, 1.3125rem) / 1.45, -.012em, --text-2
   body     17px / 1.55, -.011em        small 15px / 1.5        meta 13px / 1.4, 500
   numerals num, tabular-nums: 40px (proof strip), 44px (card headline on the site), 64–88px (finale)
   readouts mono 12–13px 500: paths, bundle IDs, "214 · 1.3 GB" in rows
   labels   13px 600 with font-variant-caps: all-small-caps and .04em tracking (styling, not ALL CAPS copy)
   eyebrow  12px 500 mono "01 · Leftover finder", the index in --accent */
h1, h2, .display, .feature h3, .brand { font-family: var(--font-display); font-weight: 600; }
.num, .proof dd, .card-h b { font-family: var(--font-num); font-weight: 600; font-variant-numeric: tabular-nums; }
```

Weight 600, never 700. The h1 keeps the family's `<mark>` highlighter on one phrase, in violet (§4.1).

### 2.3 Space, widths and radii

- Widths: `.wrap` 1080px (content), `.wide` 1240px (stages), `.read` 720px (prose, FAQ, guides, how-it-decides).
  Gutter 20px, 16px under 480.
- `main > section { padding-block: clamp(72px, 10vw, 136px) }`. Gaps are 12, 16, 24, 32, 48 or 64px.
  `scroll-padding-top: 84px`.
- Radii: `--r-s: 8px; --r-m: 12px; --r-l: 18px; --r-xl: 26px; --r-btn: 12px`.

### 2.4 Light and depth

Every shadow and hairline is the brand's ink at an alpha. `--ink` is violet-black (`22 18 40`) in light; in dark every
shadow is black at .5–.8 and the hairline becomes a 1px light rim. Never animate `box-shadow` or `filter`.

| Token | Role | Light recipe |
|---|---|---|
| `--hi` | lit top edge on raised surfaces | `rgb(255 255 255 / .9)`; dark `/ .07` |
| `--z1` | hairline plus contact: rows, pills, the header | `0 0 0 .5px ink/.12, 0 1px 2px ink/.05` |
| `--z2` | porcelain card | `inset 0 1px 0 var(--hi), 0 0 0 .5px ink/.12, 0 2px 4px ink/.04, 0 12px 28px -12px ink/.16` |
| `--shadow` | a floating object (the Trace Report card, a window shot) | `0 0 0 .5px ink/.22, 0 2px 4px ink/.06, 0 24px 48px -16px ink/.30, 0 64px 128px -32px ink/.34` |
| `--cap` | key-caps (buttons, the tray, slabs) | `inset 0 1px 0 var(--hi), 0 0 0 .5px ink/.18, 0 1px 2px ink/.08, 0 2px 0 var(--cap-side), 0 6px 14px -6px ink/.14` |
| `--slab` | a leftover slab: lit top, violet-tinted long shadow | `inset 0 1px 0 var(--hi), 0 0 0 .5px ink/.16, 0 14px 28px -12px rgb(var(--violet-ink) / .30)` |

### 2.5 Tokens (the two `:root` blocks, ready to paste)

```css
:root {
  color-scheme: light dark;
  /* contrast(), light, worst of bg / bg-alt / card: text 15.42:1, text-2 5.50:1, accent 5.77:1;
     on-button on button 8.11:1, on hover 6.82:1. (Checked with build_site.py's formula, 2026-10-03.) */
  --bg: #f6f5fb; --bg-alt: #eceaf5; --card: #ffffff;                   /* cool paper: the desk in full daylight */
  --text: #15131f; --text-2: #5f5a76; --accent: #5a44c4;               /* violet as text needs this depth on paper */
  --button: #a99bff; --button-hover: #9a8bf7; --on-button: #0f0b1e;     /* the dusk key-cap, near-black label */
  --line: #dddaea; --header: rgb(250 249 253 / .74); --hi: rgb(255 255 255 / .9);
  --ink: 22 18 40;                                                      /* violet-black: every shadow and hairline */
  --ok: #1a7f37; --bad: #d93025;                                        /* dots and symbols only, never measured text */
  /* The world: the afterglow by day. Violet above, teal at the horizon; the horizon line is the key light. */
  --sky-top: #e9e4fb; --sky-low: #d6efec; --desk: #f1f0f8; --desk-ink: 22 18 40;
  --horizon: #5fd0c3; --horizon-core: #e8fffb; --glow: rgb(63 184 176 / .22); --pool: rgb(63 184 176 / .12);
  --violet: #a99bff; --violet-ink: 90 68 196; --mark: rgb(169 155 255 / .45);
  --grain: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.85' numOctaves='3' stitchTiles='stitch'/%3E%3CfeColorMatrix values='.33 .33 .33 0 0 .33 .33 .33 0 0 .33 .33 .33 0 0 0 0 0 0 .04'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
  /* Key-caps and slabs. */
  --cap-top: #ffffff; --cap-bot: #f1f0f8; --cap-side: #cfcbe0;
  --cap: inset 0 1px 0 var(--hi), 0 0 0 .5px rgb(var(--ink) / .18), 0 1px 2px rgb(var(--ink) / .08), 0 2px 0 var(--cap-side), 0 6px 14px -6px rgb(var(--ink) / .14);
  --cap-down: inset 0 1px 0 var(--hi), 0 0 0 .5px rgb(var(--ink) / .18), 0 1px 0 var(--cap-side);
  --slab-top: #fdfcff; --slab-bot: #efedf8;
  --slab: inset 0 1px 0 var(--hi), 0 0 0 .5px rgb(var(--ink) / .16), 0 14px 28px -12px rgb(var(--violet-ink) / .30);
  --z1: 0 0 0 .5px rgb(var(--ink) / .12), 0 1px 2px rgb(var(--ink) / .05);
  --z2: inset 0 1px 0 var(--hi), 0 0 0 .5px rgb(var(--ink) / .12), 0 2px 4px rgb(var(--ink) / .04), 0 12px 28px -12px rgb(var(--ink) / .16);
  --shadow: 0 0 0 .5px rgb(var(--ink) / .22), 0 2px 4px rgb(var(--ink) / .06), 0 24px 48px -16px rgb(var(--ink) / .30), 0 64px 128px -32px rgb(var(--ink) / .34);
  --glare: rgb(90 68 196 / .07);                                        /* white can't shine on white: a violet spot */
  /* The Trace Report card is an object with fixed colours in both schemes (role="img", not measured). */
  --card-top: #0e0b1f; --card-bot: #141827; --card-text: #eef0f7; --card-2: #a3a8ba; --card-accent: #b7a8ff;
  --font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI Variable Text", "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --font-display: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI Variable Display", "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --font-num: ui-rounded, "SF Pro Rounded", var(--font);
  --font-mono: ui-monospace, "SF Mono", SFMono-Regular, Menlo, "Cascadia Mono", Consolas, monospace;
  --r-s: 8px; --r-m: 12px; --r-l: 18px; --r-xl: 26px; --r-btn: 12px;
  /* Motion and depth (docs/MOTION.md §1.2, §1.7). */
  --ease-out: cubic-bezier(.16, 1, .3, 1); --ease-spring: cubic-bezier(.34, 1.56, .64, 1); --ease-in-out: cubic-bezier(.65, 0, .35, 1);
  --t-fast: .16s; --t-base: .32s; --t-slow: .7s; --t-hero: 1.1s;
  --persp-scene: 1600px; --persp-card: 900px;
}
@media (prefers-color-scheme: dark) {
  :root {
    /* worst: text 14.78:1, text-2 7.11:1, accent 8.06:1; on-button on button 8.11:1, hover 6.82:1 */
    --bg: #0c0e15; --bg-alt: #12151e; --card: #191d28;                 /* cool near-black, never #000: the desk before sunrise */
    --text: #eef0f7; --text-2: #a3a8ba; --accent: #b7a8ff;
    --line: #262b38; --header: rgb(14 16 24 / .76); --hi: rgb(255 255 255 / .07); --ink: 0 0 0;
    --ok: #34d26b; --bad: #ff5a4f;
    --sky-top: #0e0b1f; --sky-low: #16303a; --desk: #0f1118; --desk-ink: 0 0 0;
    --horizon: #7fe3d6; --horizon-core: #effffc; --glow: rgb(63 184 176 / .26); --pool: rgb(63 184 176 / .10);
    --violet: #a99bff; --violet-ink: 169 155 255; --mark: rgb(169 155 255 / .34);
    --grain: /* the same SVG with the last matrix value .06 */;
    --cap-top: #262b38; --cap-bot: #191d28; --cap-side: #07080c;
    --cap: inset 0 1px 0 rgb(255 255 255 / .12), 0 0 0 1px rgb(255 255 255 / .08), 0 2px 0 var(--cap-side), 0 10px 20px -10px rgb(0 0 0 / .8);
    --cap-down: inset 0 1px 0 rgb(255 255 255 / .12), 0 0 0 1px rgb(255 255 255 / .08), 0 1px 0 var(--cap-side);
    --slab-top: #2a2f3d; --slab-bot: #1e2230;
    --slab: inset 0 1px 0 rgb(255 255 255 / .10), 0 0 0 1px rgb(255 255 255 / .08), 0 16px 32px -12px rgb(0 0 0 / .8), 0 10px 24px -14px rgb(var(--violet-ink) / .40);
    --z1: inset 0 1px 0 var(--hi), 0 0 0 1px rgb(255 255 255 / .07), 0 1px 2px rgb(0 0 0 / .6);
    --z2: inset 0 1px 0 var(--hi), 0 0 0 1px rgb(255 255 255 / .08), 0 14px 36px -12px rgb(0 0 0 / .8);
    --shadow: 0 0 0 1px rgb(255 255 255 / .1), 0 24px 48px -16px rgb(0 0 0 / .8), 0 64px 128px -32px rgb(0 0 0 / .9);
    --glare: rgb(255 255 255 / .09);
  }
}
```

`layout.html`: `<meta name="color-scheme" content="light dark">`, `theme-color` `#f6f5fb` and `#0c0e15` (two metas
with `media`), no font preload. The card's fixed colours were checked too: `#EEF0F7` on `#141827` 15.5:1, `#B7A8FF`
8.45:1, `#A3A8BA` 7.45:1.

### 2.6 Shared components (the same CSS as the siblings; Aftertaste's tokens)

```css
/* Header pill: 48px, the only backdrop-filter on the page. */
.nav { height: 48px; max-width: 980px; padding: 0 6px 0 14px; border-radius: 999px; background: var(--header);
  -webkit-backdrop-filter: saturate(180%) blur(20px); backdrop-filter: saturate(180%) blur(20px);
  box-shadow: inset 0 1px 0 var(--hi), var(--z1); }
.brand { font-size: 17px; letter-spacing: -.02em; }

/* Section head: editorial, left-aligned; heading left, lede right on wide screens. */
.sec-head { display: grid; gap: 16px 64px; align-items: end; margin-bottom: clamp(40px, 5vw, 64px); }
@media (min-width: 900px) { .sec-head { grid-template-columns: 7fr 5fr; } }
.sec-head h2, .sec-head .lede { margin: 0; }

/* Primary button: a dusk key-cap. The fill darkens downward only, so the label keeps its measured contrast. */
.button { border-radius: var(--r-btn); min-height: 48px; padding: 0 22px; font: 600 16px/1 var(--font); color: var(--on-button);
  background: linear-gradient(var(--button), color-mix(in srgb, var(--button) 88%, #000));
  box-shadow: inset 0 1px 0 rgb(255 255 255 / .35), inset 0 -1px 0 rgb(0 0 0 / .18), var(--cap); }
.button.secondary { color: var(--text); background: linear-gradient(var(--cap-top), var(--cap-bot)); box-shadow: var(--cap); }
.button:active { translate: 0 1px; box-shadow: inset 0 1px 0 rgb(255 255 255 / .3), var(--cap-down); }

/* Porcelain card. */
.card { border-radius: var(--r-l); background: var(--card); box-shadow: var(--z2); }

/* Proof strip: hairlines only, no box; rounded numerals. */
.proof { display: grid; grid-template-columns: repeat(4, 1fr); gap: 0; border-block: 1px solid var(--line); }
.proof div { padding: 24px 28px 24px 0; } .proof div + div { border-left: 1px solid var(--line); padding-left: 28px; }
.proof dd { font: 600 clamp(28px, 3.2vw, 44px)/1 var(--font-num); letter-spacing: -.02em; font-variant-numeric: tabular-nums; }
@media (max-width: 720px) { .proof { grid-template-columns: 1fr 1fr; } .proof div:nth-child(odd) { border-left: 0; padding-left: 0; } }

/* Ledger: rules as a spec sheet, with a trailing mono chip. */
.rules { margin: 0; padding: 0; list-style: none; border-top: 1px solid var(--line); }
.rules li { display: grid; grid-template-columns: 1fr auto; gap: 4px 24px; padding: 20px 0; border-bottom: 1px solid var(--line); }
.rules h3 { margin: 0; font: 600 17px/1.3 var(--font); letter-spacing: -.015em; }
.rules p { margin: 0; color: var(--text-2); font-size: 15px; }
.rules code { grid-column: 2; grid-row: 1 / span 2; align-self: center; }

/* FAQ: one grouped panel with hairline rows. "+" turns into "×", no JS. */
.faq-list { border-radius: var(--r-l); background: var(--card); box-shadow: var(--z2); }
.faq-list details { padding-inline: 20px; } .faq-list details + details { border-top: 1px solid var(--line); }
.faq-list summary::after { content: "+"; transition: rotate var(--t-base) var(--ease-spring); }
.faq-list details[open] summary::after { rotate: 45deg; }

/* Real screens: a scroll-snap filmstrip (§2.8). */
.film { display: grid; grid-auto-flow: column; grid-auto-columns: min(560px, 84vw); gap: 24px; overflow-x: auto;
  scroll-snap-type: x mandatory; overscroll-behavior-x: contain; padding: 8px 20px 36px; scrollbar-width: thin; }
.film figure { margin: 0; scroll-snap-align: center; }
.film img { display: block; width: 100%; height: auto; border-radius: 10px; background: var(--bg-alt); box-shadow: var(--shadow); }
.film figcaption { margin-top: 12px; font-size: 13px; color: var(--text-2); }

/* Finale: the app icon standing on the desk by the horizon. */
.finale .icon { width: 128px; height: 128px; -webkit-box-reflect: below 6px linear-gradient(transparent 62%, rgb(0 0 0 / .22)); }   /* VERIFY inside a 3D parent in Safari */

/* Small-caps labels; tier tags (the word carries the meaning, the dot carries the colour). */
.label { font: 600 13px/1.3 var(--font); font-variant-caps: all-small-caps; letter-spacing: .04em; color: var(--text-2); }
.tag { display: inline-flex; gap: 6px; align-items: center; padding: 2px 9px; border-radius: 999px; font: 600 12px/1.4 var(--font); color: var(--text);
  background: color-mix(in srgb, var(--tag, var(--text-2)) 14%, transparent); box-shadow: 0 0 0 .5px color-mix(in srgb, var(--tag, var(--text-2)) 35%, transparent); }
.tag::before { content: ""; width: 6px; height: 6px; border-radius: 50%; background: var(--tag, var(--text-2)); }
.tag.violet { --tag: var(--violet); } .tag.ok { --tag: var(--ok); } .tag.bad { --tag: var(--bad); }
```

Tier chips on the site: `.tag.violet` "High", `.tag` "Medium", `.tag` "Review", `.tag` "Hands off", `.tag` "Needs
admin". Only High gets the violet dot (it is the only preselected tier); the word does the rest.

### 2.7 Accessibility media

```css
@media (prefers-contrast: more) { html[lang] { --grain: none; --glare: transparent; --glow: transparent; --pool: transparent; }
  .card, details, .nav, .button, .tag, .proof, .faq-list, .note, .slab, .tray, .report { box-shadow: 0 0 0 2px var(--text); } .finale .icon { -webkit-box-reflect: unset; } }
@media (prefers-reduced-transparency: reduce) { .nav { -webkit-backdrop-filter: none; backdrop-filter: none; background: var(--card); } }
@media (forced-colors: active) { .button, .card, details, .tag, .proof div, .nav, .note, .slab, .tray, .report, .outline { border: 1px solid CanvasText; } }
@media print { html[lang] { color-scheme: light; --bg: #fff; --bg-alt: #fff; --card: #fff; --text: #000; --text-2: #333; --grain: none; }
  .site-header, .site-footer, .skip, .stage, .finale, .film { display: none; } }
```

`html[lang]` (0,1,1) beats `:root` (0,1,0) and does not match the checker's `:root\s*\{` regex. Also: visible 3px
violet focus rings, 44px hit areas, content visible without JS, every image with `width`/`height`, no `style=""`.

### 2.8 Imagery

- **Hero:** an HTML scene (0 image bytes, sharp at any DPI, follows the scheme). Its copy is the `leftovers` demo
  scenario (BUILD_PLAN §9), Orbit Meet 6.2: "214 files · 1.3 GB · 2 launch agents · 1 privileged helper", "Looked in
  16 of 17 places. 1 protected by macOS." Caption: "Illustration with sample data." and, as on every page, the
  not-affiliated line.
- **Real screens** below the fold at half their pixel width: the preview with the residue bar, the confirm sheet, the
  result with Undo, the Trace Report; `<picture>` with a dark `<source>`, `loading="lazy"`, `decoding="async"`, real
  `alt`. Ship the section only once `screens.yml` captures are committed to `site/static/shots/`, watermarked
  "Sample data".
- The README hero is the preview capture over a strip of the sky gradient, composited by CI (BUILD_PLAN §9), and the
  README says so.

## 3. Home page, section by section (12 blocks)

1. **Header pill** (§2.6): 22px icon and wordmark; "How it decides", "What it reads", "Guides", "Download" at 14px/500
   `--text-2`; a secondary key-cap "Source" and a 36px dusk "Download".
2. **Hero: the desk** (§4). Left copy, right scene, full-bleed band, no box.
3. **Proof strip** in rounded numerals: "0 · permissions asked", "0 · network calls", "2 · verbs: Trash and Undo",
   "100 % · of moves in the journal". The last gets a 6px `--ok` dot, the one LED. (Copy owner confirms wording
   against BUILD_PLAN §8.)
4. **"Finder removes the app. This is what it leaves."** Two objects: left, a dimmed Finder-style column of the
   `~/Library` folders with the five that still hold Orbit Meet marked by a violet tick (`Caches`, `Preferences`,
   `Application Support`, `Saved Application State`, `LaunchAgents`), `opacity: .6`, `--text-2`; right, overlapping
   it by −30px, the Aftertaste group card (`.card`, `--shadow`, `data-tilt` 7°): the app's symbol in a well, "Orbit
   Meet 6.2", "214 files · 1.3 GB · not installed", the residue bar (§4.4), one row with its why line: "Caches ·
   412 MB · High · Rebuilt automatically. Folder name is the app's bundle ID." A 1px violet line joins the two.
5. **"How it decides."** `.sec-head`, then a 5-item `.rules` ledger with mono chips: "The folder carries the app's
   exact bundle ID" `exact id`; "It rebuilds or only resets" `cache · logs · state`; "It may hold your data" `medium`;
   "Several apps may share it" `review`; "It is Apple's, running, synced or protected" `hands off`. Under it one
   line: "Only High is ticked when a scan appears. Medium needs the per-app Include my data control. Review moves one
   item at a time." A link to the how-it-decides page.
6. **"To the Trash, with Undo."** The layered slabs as a site object (§4.4 `.slab`): five slabs in a column,
   depth-stacked, each a raised tile with the class, the rounded size and the tier chip; below it the receipt as a
   mono line: "Re-checked right before each move · same file, same place, app not running · Trash, never delete ·
   every move in the journal · Undo from History until you empty the Trash". No motion here beyond reveal; the peel
   lives in the hero.
7. **"What it reads. What it never does."** A two-column `.rules` ledger: left "Reads" (folder and file names and
   sizes in your Library, the list of installed apps, each app's Info.plist and signature, three read-only system
   commands for Erase readiness), right "Never" (no permissions asked, no network, no file contents, no helper or
   root, no deleting: Trash only, no toggling of settings, nothing inside iCloud). Honesty is part of the trust.
8. **"What no app can erase."** `.sec-head` with the lede "Moving to the Trash does not erase anything. Neither does
   anything else an app can do on a modern Mac." Then the plain-sentence threat table from `ReadinessText.threats()`
   as a `.rules` ledger (who could read old data; what helps), ending with the line "Need to be sure? Apple's Erase
   All Content and Settings destroys the key." linking the guide G3. No scare copy, no numbers.
9. **Real screens.** The `.film` strip (§2.8). Caption: "Real screens, captured by CI from the app with sample data."
10. **FAQ.** Sticky head left (5), the grouped `.faq-list` right (7): "Does dragging an app to the Trash remove
    everything?", "Will this delete my documents?", "Why is something listed but not ticked?", "Why can't it remove a
    launch agent?", "Is it really free?", "Why is the app unsigned?".
11. **Finale band:** the desk again (horizon at the top, pool below), the icon at 176px standing in the pool with its
    reflection, "See what's left. It's free." in display, the dusk key-cap, the trust line.
12. **Footer:** the `--bg-alt` slab, a 0.5px ink hairline on top, mono column titles, the version tag, the official
    sources line, and the fixed line "Aftertaste is not affiliated with or endorsed by any app it detects."

(Block 8, "What no app can erase", is Aftertaste's addition to the siblings' eleven.)

## 4. Hero: the desk (the 3D product scene)

### 4.1 Copy, left, 5 of 12 columns (nothing here moves)

Eyebrow `<b>01</b> · Leftover finder · macOS 13 or later` in 12px mono, the index in `--accent`; h1
`What an app <mark>left behind.</mark>`; the lede "Find what apps leave behind. See why. Move it to the Trash. Undo."
(the fixed tagline, BUILD_PLAN §8) followed by "Aftertaste shows every leftover with the reason it belongs to the
app, ticks only what rebuilds itself, and keeps a journal so you can put anything back."; the dusk key-cap "Download
free" and the secondary "View source"; the mono trust line "Free · No permissions · No network · Nothing leaves your
Mac".

```css
.hero h1 mark { color: inherit; padding: 0 .06em; background: linear-gradient(transparent 56%, var(--mark) 56% 90%, transparent 90%);
  -webkit-box-decoration-break: clone; box-decoration-break: clone; }
```

### 4.2 The scene, right, 7 of 12 columns, no box

The `.hero` section itself is the band: full-bleed, no radius, no border; its background is the afterglow (violet at
the top, teal at the horizon, the desk below). Back to front: the horizon line (the key light) far back, the desk
plane, the outline where the app stood with the layered slabs beside it, the Trash tray at the desk's right edge, and
the printed Trace Report card in front at the right.

```html
<section class="hero dawn" aria-labelledby="hero-h">
  <div class="wide hero-grid">
    <div class="hero-copy">…§4.1…</div>
    <div class="stage" data-tilt>
      <div class="scene" id="hero-scene">
        <i class="horizon" aria-hidden="true"></i>                                 <!-- Z -220: the key light -->
        <i class="desk" aria-hidden="true"></i>                                    <!-- the plane everything stands on -->
        <div class="stack" aria-hidden="true">                                     <!-- Z 0: where the app stood -->
          <i class="appicon"><b></b></i>                                           <!-- the icon tile; at rest it has left -->
          <i class="outline"></i>                                                  <!-- the dashed after-image -->
          <ul class="slabs">                                                       <!-- the layers, depth-stacked -->
            <li><span>Caches</span><b>412 MB</b><em class="tag violet">High</em></li>
            <li><span>Settings</span><b>1.2 MB</b><em class="tag violet">High</em></li>
            <li><span>Saved state</span><b>96 KB</b><em class="tag violet">High</em></li>
            <li><span>Your data</span><b>880 MB</b><em class="tag">Medium</em></li>
            <li class="listed"><span>Launch agents</span><b>2</b><em class="tag">Hands off</em></li>
          </ul>
        </div>
        <div class="tray" aria-hidden="true"><span class="label">Trash</span><b class="count">4</b></div>   <!-- Z +40 -->
        <div class="report-wrap">                                                  <!-- Z +80 -->
          <figure class="report" id="hero-card" role="img" aria-label="Illustration with sample data: the Aftertaste Trace Report card. Orbit Meet 6.2 left behind: 214 files, 1.3 GB, 2 launch agents, 1 privileged helper. Looked in 16 of 17 places, 1 protected by macOS. Launch agents and helpers are listed, not removed. macOS 26.1, scanned 2026-10-03, measured on this Mac, nothing sent anywhere. On the back: this is a list of what was found in the places listed above; it is not proof that anything was erased.">
            <div class="face front">
              <p class="card-brand"><svg aria-hidden="true"><use href="#i-mark"/></svg>Aftertaste<span class="tag violet">Sample data</span></p>
              <p class="card-h"><b>Orbit Meet 6.2</b> left behind</p>
              <p class="card-figs"><b>214</b> files · <b>1.3</b> GB · <b>2</b> launch agents · <b>1</b> privileged helper</p>
              <p class="card-cov">Looked in 16 of 17 places. 1 protected by macOS.<br>Launch agents and helpers are listed, not removed.</p>
              <p class="card-prov">macOS 26.1 · scanned 2026-10-03 · measured on this Mac, nothing sent anywhere<span>everydayopen.github.io/aftertaste</span></p>
            </div>
            <div class="face back">
              <p class="card-foot">This is a list of what was found in the places listed above. It is not proof that anything was erased.</p>
              <p class="card-nc"><span class="label">Not covered</span>keychain items · login and background item records · Launch Services and Spotlight entries · iCloud data · other users · backups and snapshots</p>
            </div>
          </figure>
          <button class="button secondary report-flip" type="button" data-flip aria-controls="hero-card" aria-pressed="false" hidden>Turn the card over</button>
        </div>
        <button class="button stack-move" type="button" data-sweep="Reset demo" data-sweep-said="Sample: moved 4 items to the Trash, 1 listed only" data-sweep-reset="Demo reset" aria-controls="hero-scene" aria-pressed="false" hidden>Move 4 items to Trash</button>
        <p class="sr-only" role="status" aria-live="polite" data-sweep-status></p>
      </div>
    </div>
  </div>
  <p class="caption">Illustration with sample data. Aftertaste is not affiliated with or endorsed by any app it detects.</p>
</section>
```

Both buttons are hidden until `motion.js` runs; without JS the picture is complete and still in the found state. The
move button sits under the slab column (not over a drawn key-cap: nothing in this scene pretends to be a control), the
flip button under the card. The figure's `aria-label` describes both faces, so the flip changes nothing for assistive
tech beyond the button's `aria-pressed`; the sweep announces through the live region.

```css
.dawn { background: var(--grain), linear-gradient(var(--sky-top), var(--sky-low) 46%, var(--desk) 46.5%); }
.hero-grid { display: grid; gap: 40px; align-items: center; }
@media (min-width: 900px) { .hero-grid { grid-template-columns: 5fr 7fr; } }
.stage { position: relative; min-height: 560px; perspective: var(--persp-scene); perspective-origin: 50% 36%; }
.scene { position: absolute; inset: 0; transform-style: preserve-3d; }
/* The horizon: a thin bright line far back where the sky meets the desk, with the teal glow above and below it. The only light. */
.horizon { position: absolute; left: -12%; right: -12%; top: 46%; height: 2px; border-radius: 1px; transform: translateZ(-220px);
  background: linear-gradient(90deg, transparent, var(--horizon) 18%, var(--horizon-core) 50%, var(--horizon) 82%, transparent);
  box-shadow: 0 0 18px var(--glow), 0 0 80px var(--glow); }
/* The desk: a flat plane with the horizon's pool on it. The mask sits on this flat plane, never on the preserve-3d scene (MOTION §1.6). */
.desk { position: absolute; left: -30%; right: -30%; bottom: -6%; height: 60%; transform-origin: 50% 0; transform: rotateX(78deg);
  background: radial-gradient(45% 40% at 50% 0, var(--pool), transparent 70%), repeating-linear-gradient(90deg, rgb(var(--desk-ink) / .05) 0 1px, transparent 1px 96px);
  -webkit-mask-image: radial-gradient(70% 90% at 50% 0, #000 10%, transparent 72%); mask-image: radial-gradient(70% 90% at 50% 0, #000 10%, transparent 72%); }
/* The stack: the icon's footprint and the layers beside it, standing on the desk. */
.stack { position: absolute; left: 6%; top: 24%; width: 420px; height: 300px; transform-style: preserve-3d; }
.appicon { position: absolute; left: 0; top: 40px; width: 120px; height: 120px; border-radius: 27%; opacity: 0;
  background: linear-gradient(160deg, #5fd0c3, #5a44c4); transform: translate3d(0, -140px, 140px) scale(.9); }   /* rest: it has left */
.appicon b { position: absolute; inset: 30%; border-radius: 50%; border: 9px solid rgb(255 255 255 / .9); }       /* a fictional "Orbit Meet" mark */
.outline { position: absolute; left: 0; top: 40px; width: 120px; height: 120px; border-radius: 27%; border: 2px dashed var(--accent); opacity: .55; }
.slabs { position: absolute; left: 160px; top: 0; margin: 0; padding: 0; list-style: none; width: 260px; transform-style: preserve-3d; }
.slabs li { position: absolute; left: 0; display: grid; grid-template-columns: 1fr auto auto; gap: 10px; align-items: center; width: 100%; padding: 10px 12px; border-radius: var(--r-m);
  background: linear-gradient(var(--slab-top), var(--slab-bot)); color: var(--text); font: 500 13px/1.2 var(--font); box-shadow: var(--slab);
  transform: translate3d(var(--dx), var(--dy), var(--dz)) scale(1); }
.slabs li::before { content: ""; position: absolute; inset: 0 var(--r-m) auto; height: 2px; border-radius: 1px; background: var(--violet); opacity: .9; }   /* the lit edge: violet on High */
.slabs li:not(:has(.violet))::before { background: var(--hi); }                                                  /* VERIFY :has in Firefox ≥ 121; fallback: the .listed/.medium class */
.slabs b { font-family: var(--font-num); font-variant-numeric: tabular-nums; }
.slabs .listed { opacity: .72; }
.slabs li:nth-child(1) { --dx: 0px;   --dy: 0px;   --dz: 0px; }
.slabs li:nth-child(2) { --dx: -10px; --dy: 58px;  --dz: -24px; }
.slabs li:nth-child(3) { --dx: -20px; --dy: 116px; --dz: -48px; }
.slabs li:nth-child(4) { --dx: -30px; --dy: 174px; --dz: -72px; }
.slabs li:nth-child(5) { --dx: -40px; --dy: 232px; --dz: -96px; }
/* The tray: a shallow key-cap at the desk's edge, its count hidden until the peel. */
.tray { position: absolute; right: 6%; bottom: 14%; width: 150px; height: 44px; display: flex; gap: 10px; align-items: center; justify-content: center;
  border-radius: var(--r-m); background: linear-gradient(var(--cap-top), var(--cap-bot)); box-shadow: var(--cap); transform: translateZ(40px); }
.tray .count { font: 600 15px/1 var(--font-num); font-variant-numeric: tabular-nums; opacity: 0; }
/* The card: the front-most object, 300×158 (1200×630), fixed night colours in both schemes. */
.report-wrap { position: absolute; right: 2%; top: 8%; width: 300px; transform: translateZ(80px); perspective: var(--persp-card); }
.report { position: relative; margin: 0; aspect-ratio: 1200 / 630; transform-style: preserve-3d; border-radius: 12px; }
.report .face { position: absolute; inset: 0; padding: 14px 16px; border-radius: 12px; overflow: hidden; backface-visibility: hidden; -webkit-backface-visibility: hidden;
  background: linear-gradient(var(--card-top), var(--card-bot)); color: var(--card-text); font: 11px/1.35 var(--font); box-shadow: inset 0 1px 0 rgb(255 255 255 / .08), var(--shadow); }
.report .face::after { content: ""; position: absolute; left: 0; right: 0; bottom: 18%; height: 1px; background: linear-gradient(90deg, transparent, var(--horizon), transparent); opacity: .7; }   /* the horizon printed on the card */
.report .back { transform: rotateY(180deg); }
.report.flipped { transform: rotateY(180deg); }
.card-brand { display: flex; gap: 6px; align-items: center; margin: 0 0 8px; font: 600 10px/1 var(--font); font-variant-caps: all-small-caps; letter-spacing: .06em; color: var(--card-2); }
.card-brand svg { width: 12px; height: 12px; color: var(--card-accent); } .card-brand .tag { margin-left: auto; color: var(--card-text); }
.card-h { margin: 0 0 6px; font: 600 18px/1.1 var(--font-display); letter-spacing: -.02em; } .card-h b { color: var(--card-accent); }
.card-figs { margin: 0 0 8px; font-size: 12px; } .card-figs b { font-family: var(--font-num); font-variant-numeric: tabular-nums; }
.card-cov, .card-nc { margin: 0; color: var(--card-2); }
.card-prov { position: absolute; left: 16px; right: 16px; bottom: 10px; margin: 0; display: flex; justify-content: space-between; gap: 8px; font: 500 9px/1.3 var(--font-mono); color: var(--card-2); }
.card-foot { margin: 0 0 10px; font: 600 12px/1.35 var(--font); }
.report-flip { position: absolute; left: 0; top: calc(100% + 12px); min-height: 0; padding: 8px 14px; font-size: 13px; }
.stack-move { position: absolute; left: 6%; bottom: 10%; min-height: 0; padding: 10px 16px; font-size: 14px; transform: translateZ(2px); }
.report-flip[hidden], .stack-move[hidden] { display: none; }
@media (max-width: 900px) { .tray, .report-wrap { display: none; } .stack { position: static; width: min(420px, 100%); height: 320px; margin: 24px auto 0; } .stack-move { position: static; margin-top: 12px; } .stage { min-height: 0; } }
```

**Planes** (4, within MOTION §1.2's cap): horizon −220, the stack at 0 (its slabs step back to −96 inside it), the
tray +40, the card +80. The pointer tilts the whole scene up to 5°, which parallaxes the slabs against the outline and
the card against the desk: the depth cue a flat frame can't give.

**Sequence** (2.6 s once, then still), **the peel** (0.9 s on the move button) and **the flip** (0.6 s on the card
button) are specified in MOTION §2. Reduce Motion, print and no-JS show the found state; the buttons swap states
instantly under Reduce Motion.

### 4.3 Inline glyphs (the page's sprite; neutral, no vendor marks)

`#i-mark` (the app mark: a rounded square outline with its top-right corner lifted away as a small solid tile, §7),
`#i-ok` (the check in a circle), `#i-down` (download), and the class glyphs `#k-cache` (a stack of three lines),
`#k-settings` (a slider), `#k-state` (a window), `#k-data` (a folder), `#k-launch` (a play triangle in a square),
`#k-shared` (two overlapping squares), each a 24-viewBox stroke icon drawn to match the SF Symbols the app uses
(§6.1), so the replica and the CI captures agree.

### 4.4 Section recipes

- **Slabs (`.slab`, the "To the Trash, with Undo" section):** the hero's `.slabs` rules reused as a static column
  (`--dz` 0, `--dx` 0, so they read as a stack of tiles with 8px gaps), `data-tilt` 5° on the column, not per slab.
  Under Reduce Motion, static.
- **Residue bar (`.rbar`, the group card in block 4 and the how-it-decides page):** one bar per app, segments per
  class with `flex-grow` their bytes and `min-width: 56px` (lesson f), 8px radius, a 2px violet lit edge on segments
  whose class is High, `var(--slab-top)` fill otherwise; **labels never live inside segments**: a legend row below
  (`.rbar-key`, 13px, "Caches 412 MB · Settings 1.2 MB · Your data 880 MB …"), so nothing truncates. Under the bar
  one 13px line: "1.2 GB selected (rebuilds itself) · 880 MB not selected".
- **Readout rows** (the Finder column, the group card's row): a 3px violet tick on the leading edge of a High row
  (`::before`, 10px inset), none on the others; title 15px 600, the `~` path in mono `--text-2`, the rounded size
  right-aligned, then `.tag`. Hairlines between rows, never cards.
- **Receipt** (the move copy): `--bg-alt`, 12px radius, 13px mono, `--text-2`, dots between clauses.
- **Finale:** `.finale .icon` from §2.6 standing in a `.desk` copy's pool with a `.horizon` copy at the band's top.

## 5. Sub-pages

- **Download:** a 240px dawn band with the icon standing in the horizon's pool, the h1, the dusk key-cap, the
  requirements line, three key-cap steps (Open the zip · Drag to Applications · Right-click, Open the first time: the
  Gatekeeper step, with the SHA-256 line), and the official-sources line.
- **What it reads (safety):** the reading layout; the §3-7 ledger in full, then the safety rules from BUILD_PLAN §3 as
  a numbered `.rules` list with mono chips (`trashItem`, `0600`, `lstat`, `O_NOFOLLOW`, `3 commands`). Prints clean.
- **How it decides:** the reading layout; the five rules with a worked example per tier (High, Medium, Review, Hands
  off, Needs admin), each example a readout row with its why line; the residue bar for the sample app; the never-list
  as a mono block; the "Not covered" line; a "Report a wrong match" dusk key-cap linking the issue template.
- **Guides** (`/guides/`, index plus three; the `<!--meta {…}-->` first line, `article.read.prose.guide`, an eyebrow
  `G1 · Guide · Checked <date> · macOS`, a `.summary` box "The short answer" with three numbered sentences, `h2`s with
  ids, a sources list at the end, the not-affiliated line). Facts come from `docs/next/app4-research-forensics.md` in
  the Whydunit repo and from the residue-map research; every number names its source and date. The copy owner fills
  the prose; the outlines are fixed here:
  - **G1 "Does uninstalling a Mac app delete everything?"** Short answer: no; dragging to the Trash removes the
    bundle, not what the app wrote to your Library; for most apps something stays. Sections: *What the Trash removes*
    (the `.app` and nothing else); *What stays, by folder* (a readout-row list of Preferences, Application Support,
    Caches, Containers and Group Containers, Saved Application State, HTTPStorages and WebKit, Logs, LaunchAgents, and
    the `/Library` items: helpers, daemons, receipts), with the Homebrew cask `zap` figures (4,734 of 7,772 casks list
    leftover paths; Preferences 75.5 %, Application Support 64.9 %, Saved Application State 48.1 %, Caches 46.5 %,
    2026-10-03); *How to look yourself* (Finder › Go › Go to Folder, `~/Library`, what a bundle ID looks like);
    *What is worth keeping* (settings you may want back, documents in Application Support, licence files); *What no
    app sees* (keychain items, login and background item records, Launch Services and Spotlight entries, iCloud
    copies, other users, backups and snapshots). Ends with the residue bar for the sample app.
  - **G2 "Is it safe to delete ~/Library leftovers?"** (the title keeps "safe" because it is the question people
    type; the body answers without the word.) Short answer: caches, logs and saved state come back by themselves;
    settings reset the app; Application Support and Containers can hold your own documents; shared folders belong to
    more than one app. Sections: *Rebuilt automatically* (Caches, Logs, Saved Application State, HTTPStorages, WebKit:
    the only folders a scan ticks by default); *Reset, not lost* (Preferences: what a `.plist` holds, why a licence
    key or a sign-in can live there); *May be your only copy* (Application Support, Containers, Group Containers:
    notes, recordings, databases; look before you tick; reinstalling will not bring them back); *Shared by several
    apps* (vendor folders such as Adobe, Microsoft, Google, Mozilla, JetBrains; Group Containers of one developer
    team: one app gone, the other still using it); *Leave these alone* (anything `com.apple.*`, anything running,
    launch agents and daemons: removing the plist does not stop a loaded job; `~/Library/Mobile Documents` and
    CloudStorage: a move there syncs everywhere); *Trash, not delete* (why a move you can undo beats `rm`; Finder's
    Put Back may not work for items moved by apps; local snapshots keep the space for a while). Ends with the
    five-tier ledger.
  - **G3 "Can deleted files be recovered on a Mac? (APFS, SSD, FileVault)"** Short answer: emptying the Trash makes a
    file's blocks reusable, nothing more; on an Apple silicon or T2 Mac those blocks are ciphertext to anyone without
    the keys; copies in snapshots, Time Machine and iCloud are untouched. Sections: *What the Trash and Empty Trash
    do*; *Snapshots and Time Machine* (local snapshots live on the same disk, kept up to 24 hours or until space is
    needed; a file that existed when a snapshot was taken is still readable from it; an external Time Machine disk is
    a second copy; Apple Support 102154, Eclectic Light 2026-01-31); *iCloud* (Recently Deleted keeps items 30 days;
    every signed-in device has its own copy); *Why overwriting does not do what it says on a Mac* (NIST SP 800-88r2,
    September 2025: on flash with spare cells an overwrite "should be avoided"; Wei et al., FAST 2011: single-file
    overwrite left 4 % to 75 % of a file on SSDs; Apple removed Secure Empty Trash in OS X 10.11, security note
    CVE-2015-5901, and `srm` is absent since macOS 10.12; `diskutil` refuses a free-space overwrite on APFS); *What
    encryption changes* (every APFS volume on Apple silicon and T2 Macs has a volume key in the Secure Enclave even
    with FileVault off; FileVault ties that key to your password; Erase All Content and Settings destroys the key,
    which is the strongest erase Apple offers; an Intel Mac without T2 has no hardware encryption at rest); *The
    honest table* (the scenario rows from forensics §3, in plain sentences: Apple silicon with FileVault on, Apple
    silicon with FileVault off, Intel without T2, external HDD, external SSD or USB stick, iCloud-synced files); *What
    to do* (turn FileVault on; before selling or passing on a Mac use Erase All Content and Settings; format external
    disks as encrypted APFS so a later erase is a key change; keep backups you mean to keep); *What Aftertaste does
    here* (the Erase readiness panel reads FileVault state, storage type and the local snapshot count, and says so in
    plain words; it moves files to the Trash and never claims more). Lines that quote a banned phrase to say the app
    never uses it carry `no-claim-ok`.
- **Changelog:** release `.card`s with a 2px violet rail on the left and the version in a mono tag.
- **404:** the dawn band with the horizon and an outline with nothing beside it: "Nothing here. Nothing left behind,
  either." (copy owner to confirm).
- **`llms.txt`:** plain text, the pitch, the trust box, the "will never say" list marked `no-claim-ok`, the
  not-affiliated line.

## 6. The app (macOS 13; macOS 14+ and 26 only in `Compat.swift`). Written, not compiled.

**Material hierarchy, in order:** the system window (sidebar and toolbar stay system; on macOS 26 the SDK makes them
glass by itself) → `Dawn` (a static wash: the afterglow along the top edge of stage screens) → porcelain surfaces for
content groups → controls (glass only on `barSurface()`). One accent; tier only as a tag word plus dot; status only as
symbol tint. One lifted object per screen. Nothing moves at idle.

### 6.1 `App/DesignSystem/Tokens.swift`

Copy Tirekick's `Space`, `Radius` (add `plate = 18, tile = 14, row = 12, chip = 8`), `Motion` (plus `stagger`,
MOTION §3.1), `surface`, `OnFloor`, `Horizon`, `Metric`, `Tag`, `KeyCapStyle`, `HoverTilt`, `flip`, `FlipFaces`,
`CopyButton`, `copyToPasteboard`, `well`, `lifted`, `terminal` verbatim (the Tirekick `AppModel.Step` references in
`Bay`/`StepBar`/`FloatingBar` are not copied), then change only these:

```swift
/// docs/DESIGN.md §1, §6. Violet is the one accent ("left behind"); green only for Nothing found and a moved row's
/// check; red only on a failed row's symbol. Teal exists only inside `Dawn` and the card: it is sky, not UI.
enum Brand {
    /// Violet-black: the soft shadow under porcelain surfaces is tinted with it, never neutral grey (rule 3).
    static let ink = Color(red: 0.086, green: 0.071, blue: 0.157)                                     // #161228
    /// The dusk key-cap fill and every violet fill. Near-black text on it (8.1:1).
    static let dusk = Color(red: 0.663, green: 0.608, blue: 1.0)                                      // #A99BFF
    static let onDusk = Color(red: 0.059, green: 0.043, blue: 0.118)                                  // #0F0B1E
    /// Violet as text, a symbol or the outline: readable on paper and on the night desk (5.8:1 / 8.1:1).
    static let duskInk = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.718, green: 0.659, blue: 1.0, alpha: 1)                              // #B7A8FF
            : NSColor(srgbRed: 0.353, green: 0.267, blue: 0.769, alpha: 1)                            // #5A44C4
    })
    /// The horizon. Never on a control, a chip or text.
    static let horizon = Color(red: 0.498, green: 0.890, blue: 0.839)                                 // #7FE3D6
    static let skyTop = Color(red: 0.055, green: 0.043, blue: 0.122)                                  // #0E0B1F
    static let skyLow = Color(red: 0.086, green: 0.188, blue: 0.227)                                  // #16303A
}

/// The afterglow behind stage screens (welcome, the result sheet, Erase readiness, the Trace Report): the plain
/// window plus the sky along the top edge and the horizon line under it, as a static wash. Increase Contrast gets
/// the plain window. Drawn once per size.
struct Dawn: View {
    var strength = 1.0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark = scheme == .dark
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)
            if contrast != .increased {
                VStack(spacing: 0) {
                    // Violet to teal, fading into the window: the sky before sunrise, or by day at a quarter strength.
                    LinearGradient(colors: [Brand.skyTop.opacity((dark ? 0.9 : 0.12) * strength), Brand.skyLow.opacity((dark ? 0.7 : 0.14) * strength), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 220)
                    Spacer(minLength: 0)
                }
                // The horizon: one key light per scene (rule 2). A 1pt line with a soft pool below it.
                Horizon(tint: Brand.horizon, width: 560, soft: true).opacity(0.9 * strength).offset(y: 150)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The one prominent button per screen (Move 14 items to Trash, Undo all, Continue): a dusk key-cap with near-black
/// text, a lit top edge and a violet-black lip; a press sinks 1pt. No glow: the light comes from the horizon, not the
/// button. `.keyboardShortcut(.defaultAction)` still works. Replaces .borderedProminent there.
struct DuskButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Plate(configuration: configuration) }

    private struct Plate: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            let down = configuration.isPressed && !reduceMotion
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(Brand.onDusk)
                .padding(.horizontal, 18)
                .frame(minHeight: 30)
                .background(shape.fill(Brand.dusk).overlay(shape.fill(LinearGradient(colors: [.clear, Color.black.opacity(0.12)], startPoint: .top, endPoint: .bottom))))
                .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.5), Color.black.opacity(0.22)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .background(shape.fill(Color(red: 0.30, green: 0.23, blue: 0.62)).offset(y: down ? 0.5 : 1.5))   // the lip; its bottom stays put
                .contentShape(shape)
                .opacity(enabled ? 1 : 0.4)
                .offset(y: down ? 1 : 0)
                .animation(Motion.pop, value: configuration.isPressed)
        }
    }
}

extension Tier {
    /// The chip word is `displayName` (Model). Tier is carried by the word, never by colour alone (§1.1 rule 4):
    /// only High gets the violet dot, because it is the only tier a scan ticks.
    var tint: Color { self == .high ? Brand.dusk : .secondary }
}

extension ResidueKind {
    /// Neutral SF Symbols, never vendor logos (BUILD_PLAN §8). VERIFY each in the SF Symbols app: availability macOS 13 or earlier.
    var symbol: String {
        switch self {
        case .app: return "app"
        case .cache: return "square.stack.3d.up"
        case .settings: return "slider.horizontal.3"
        case .state: return "macwindow"
        case .logs: return "doc.text"
        case .cookies: return "globe"
        case .launchItem: return "play.square"
        case .yourData: return "folder"
        case .shared: return "square.on.square"
        case .system: return "lock"
        }
    }
}

extension TrashStatus {
    /// Result and History rows: a symbol in a status colour, the word beside it. Red only here, only on failed.
    var symbol: String {
        switch self {
        case .moved: return "checkmark.circle.fill"
        case .alreadyGone: return "minus.circle"
        case .changedSinceScan, .blocked, .protectedByMacOS, .locked, .dataless: return "hand.raised"
        case .failed: return "xmark.circle.fill"
        case .notAttempted: return "circle.dashed"
        }
    }
    var tint: Color {
        switch self {
        case .moved: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
    var word: String {
        switch self {
        case .moved: return "Moved to Trash"
        case .alreadyGone: return "Already gone"
        case .changedSinceScan: return "Changed since the scan"
        case .blocked: return "Left alone"
        case .protectedByMacOS: return "Protected by macOS"
        case .locked: return "Locked"
        case .dataless: return "Not downloaded"
        case .failed: return "Failed"
        case .notAttempted: return "Not attempted"
        }
    }
}

extension ReadinessText.Tone {
    /// Readiness lines: a dot beside the title. `attention` is violet, not red: the panel informs, it never alarms.
    var tint: Color {
        switch self {
        case .ok: return .green
        case .info: return .secondary
        case .attention: return Brand.dusk
        }
    }
}
```

`Tag(text, tint:)` is unchanged; `Tag(item.tier.displayName, tint: item.tier.tint)` is the tier chip. The `Metric`
default design is `.rounded` (sizes and counts are rounded; mono is for paths and bundle IDs only).

**Type in the app:** SF only. The preview total `.system(size: 40, weight: .semibold, design: .rounded)` with
`.monospacedDigit()` and `.contentTransition(.numericText())` (macOS 13); stage headlines `.system(size: 28, weight:
.semibold)` `tracking(-0.5)`; plate titles 22pt semibold; rows 13pt with a 12pt secondary line; paths and bundle IDs
`.system(.caption, design: .monospaced)`; small-caps labels only on metric labels and section headers. Radii 18
(plates), 14 (tiles, slabs), 12 (rows, inner groups), 8 (chips), 12 for the dusk button.

### 6.2 `App/DesignSystem/Compat.swift` (the only file with `#available`)

Tirekick's `barSurface()`, `capsuleBorder()` and `bounce(on:)` verbatim, plus:

```swift
extension View {
    /// Brings the app forward (the optional menu bar item's "Open Aftertaste"). `NSApp.activate()` is macOS 14.
    func activateApp() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }
}
```

The macOS 13 path is the full design. macOS 14 adds the symbol bounce on the Nothing-found check and the capsule
border on "Rescan"; macOS 26 adds glass on the two bars.

### 6.3 `Outline.swift`, `ResidueBar.swift`, `Layered.swift`: the signature objects

```swift
/// The after-image a moved row leaves: its content fades fast, a dashed violet outline of its box stays for a moment,
/// then the outline fades too. One animatable `progress` (0 = the row, 1 = gone) drives both, so a transition can
/// run it. Pure fills and strokes: ImageRenderer-safe, nothing loops.
struct Outline: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let content0 = max(0, 1 - progress * 3.3)                                       // gone by 30 %
        let trace = progress < 0.3 ? progress / 0.3 : max(0, 1 - (progress - 0.3) / 0.7) // rises, then fades by 100 %
        content
            .opacity(content0)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(Brand.duskInk)
                    .opacity(trace * 0.7)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

extension AnyTransition {
    /// A row leaving for the Trash (MOTION §3.2). Opacity only under Reduce Motion.
    static func outline(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .modifier(active: Outline(progress: 1), identity: Outline(progress: 0))
    }
}

/// One proportional bar per app: a segment per class, width by bytes with a floor so small classes stay legible, a
/// violet lit edge on segments that are ticked. Labels never live inside segments (lesson f): the legend row under
/// the bar carries class and size, and the line under that says what is selected. Pure fills, ImageRenderer-safe.
struct ResidueBar: View {
    struct Segment: Identifiable {
        let kind: ResidueKind
        let bytes: UInt64
        let ticked: Bool
        var id: String { kind.rawValue }
    }
    let segments: [Segment]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let total = max(1, segments.reduce(0) { $0 + $1.bytes })
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { g in
                let gap: CGFloat = 3, minW: CGFloat = 24
                let free = max(0, g.size.width - gap * CGFloat(max(0, segments.count - 1)) - minW * CGFloat(segments.count))
                HStack(spacing: gap) {
                    ForEach(segments) { s in
                        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
                        shape.fill(contrast == .increased ? AnyShapeStyle(.quaternary)
                                   : AnyShapeStyle(LinearGradient(colors: dark ? [Color(red: 0.165, green: 0.184, blue: 0.239), Color(red: 0.118, green: 0.133, blue: 0.188)]
                                                                                : [Color(red: 0.992, green: 0.988, blue: 1), Color(red: 0.937, green: 0.929, blue: 0.973)],
                                                                  startPoint: .top, endPoint: .bottom)))
                            .overlay(alignment: .top) { Capsule().fill(s.ticked ? Brand.dusk : Color.white.opacity(dark ? 0.12 : 0.9)).frame(height: 2).padding(.horizontal, 4).padding(.top, 1) }
                            .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 1 : dark ? 0.10 : 0.08), lineWidth: contrast == .increased ? 1 : 0.5))
                            .frame(width: minW + free * CGFloat(s.bytes) / CGFloat(total))
                    }
                }
            }
            .frame(height: 14)
            // The legend: every class named, so no segment needs a label it cannot fit.
            Text(segments.map { "\($0.kind.displayName) \(Format.bytes($0.bytes))" }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Residue by class: " + segments.map { "\($0.kind.displayName) \(Format.bytes($0.bytes))\($0.ticked ? ", selected" : "")" }.joined(separator: ", "))
    }
}

extension View {
    /// Layered depth for a result group: two faint rims offset under the surface, so a group card reads as a short
    /// stack of sheets (the leftovers beneath the outline). Static, pure strokes, no shadow on the layers themselves.
    func layered() -> some View { modifier(Layered()) }
}

private struct Layered: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
        let dark = scheme == .dark
        return content.background {
            if contrast != .increased {
                ZStack {
                    shape.fill(dark ? Color.white.opacity(0.03) : Color.white.opacity(0.6)).overlay(shape.strokeBorder(Color.primary.opacity(dark ? 0.08 : 0.06), lineWidth: 0.5)).padding(.horizontal, 12).offset(y: 6)
                    shape.fill(dark ? Color.white.opacity(0.04) : Color.white.opacity(0.8)).overlay(shape.strokeBorder(Color.primary.opacity(dark ? 0.09 : 0.07), lineWidth: 0.5)).padding(.horizontal, 6).offset(y: 3)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}
```

`Motion.stagger = 0.045` is added to `Motion` (Whydunit's value). The outline fade of a list of rows therefore
spans at most 0.36 s of stagger plus a 0.6 s fade: under 1 s for the whole list (BUILD_PLAN §8).

### 6.4 `MenuBarIcon.swift` (the optional item only; off by default)

- **The glyph** (template): the mark at 16×16, a rounded-square outline (1.5pt stroke, 3pt radius) with a 4pt gap
  cut from its top-right corner and a 4pt solid square set diagonally above that corner (the tile that left). Drawn
  with `Canvas` into an `ImageRenderer` once at launch, `isTemplate = true`, so it follows the menu bar's appearance.
  No badge, no colour, ever: the item only reopens the window (BUILD_PLAN §1), so it has nothing to count.

```swift
enum MenuBarIcon {
    static let glyph: NSImage = {
        let r = ImageRenderer(content: Mark())
        r.scale = 2
        let image = r.nsImage ?? NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = true
        return image
    }()

    private struct Mark: View {
        var body: some View {
            Canvas { ctx, sz in
                var p = Path()
                p.addRoundedRect(in: CGRect(x: 1.5, y: 2.5, width: 11, height: 11), cornerSize: CGSize(width: 3, height: 3))
                ctx.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))   // the outline
                ctx.fill(Path(roundedRect: CGRect(x: 10.5, y: 0.5, width: 4.5, height: 4.5), cornerSize: CGSize(width: 1.2, height: 1.2)), with: .color(.black))   // the tile that left
            }
            .frame(width: 16, height: 16)
        }
    }
}
```

### 6.5 Screens (BUILD_PLAN §7.1; each reachable in demo mode)

**Welcome** (`WelcomeView`, app-shell; the window's empty state, 760×560 min). Over `Dawn()`: the drop zone as the
one lifted object, a `.surface(18)` 520pt wide with a dashed violet outline inside it (`Outline`'s stroke at
`progress 0.3`, static) around `OnFloor(height: 96)` of a generic app tile (`app.dashed` symbol at 56pt in a
`well(Brand.dusk, size: 96)`), "Drop an app here" at 22pt semibold, "or" and a `.bordered` "Choose an app…"; under
it one 13pt secondary sentence "Aftertaste reads names and sizes in your Library, never contents. It asks for no
permission."; then two key-caps (`KeyCapStyle`) side by side: "Find leftovers of apps that are gone" (`magnifyingglass`)
and "Erase readiness" (`lock.shield`); the installed list as a system `List` under a small-caps "Installed" header
with a search field (`AppIcons` images at 24pt, name, version secondary, mono bundle ID on hover `.help`). The drop
zone gets `HoverTilt(max: 6, glare: true)` (one of the app's two). A "Sample data" `Tag` top-trailing in demo mode.

**First run** (`FirstRunView`, app-shell; a sheet sized to content over Welcome). The icon on `OnFloor(height: 112)`
with `HoverTilt(max: 8, glare: true)` (the second) and MOTION §3.4's arrival; "What Aftertaste reads" at 28pt; one
`.surface(16)` with two small-caps headed columns, "Reads" (`list.bullet.rectangle` names and sizes in your Library,
`app.badge.checkmark` the installed apps, `doc.text.magnifyingglass` each app's Info.plist and signature,
`terminal` three read-only commands for Erase readiness) and "Never" (`lock.open` no permissions, `wifi.slash` no
network, `doc` no file contents, `trash` "nothing deleted: Trash only, with Undo", `person.badge.key` no helper or
admin); the one `DuskButtonStyle` "Continue". VERIFY each symbol on macOS 13.

**Preview** (`PreviewView` + `GroupSection` + `ItemRow`, app-content). `NavigationSplitView`: the sidebar lists apps
(system `List` rows: the app icon at 24pt, name 13pt semibold, "214 items · 1.3 GB" secondary, under it the chips
"41 High" `.dusk` and "3 Medium"/"2 Review" when present; an orphan row says "not installed" in secondary). The
detail column's top is a stage over `Dawn(strength: 0.6)`: `PlanText.previewHeader` as a `Metric` row
(`Metric("Found", "3.4", unit: "GB")`, `Metric("Places", "41")`, `Metric("Selected", "1.2", unit: "GB")`), the first
value at 40pt rounded with `numericText`; under it the coverage line (`PlanText.coverageLine`) in 13pt secondary with
"protected by macOS" rows by name behind a disclosure (each with "Reveal in Finder" and the Full Disk Access text
steps); then one **group card per app** (`.surface(18)` + `.layered()`, the lifted objects: at most three on screen
before scrolling): header `HStack` (icon in a 32pt `well`, "Orbit Meet 6.2" 17pt semibold, "not installed" / "Running.
Quit Orbit Meet first." secondary, the per-app `Toggle("Include my data")` trailing, `.toggleStyle(.switch)`, only
when the group has Medium rows), the **`ResidueBar`**, then the rows grouped by class under small-caps class headers
each followed by its consequence line (`WhyText.consequence`) in 12pt secondary. An `ItemRow`: `Toggle` checkbox
(absent for Hands off and Needs admin; disabled while the owner runs), the class symbol in a 20pt neutral `well`, the
name 13pt semibold, the `~` path in `.caption.monospaced` secondary `truncationMode(.middle)`, trailing size rounded
`monospacedDigit` ("12 MB", "at least 3 GB", "size not measured"), the tier `Tag`, the why line 12pt secondary
`lineLimit(2)` with "Details" as a borderless disclosure (evidence lines on `terminal()`), and on hover "Reveal in
Finder" and "Copy path" as borderless buttons (`.help` on both). Review rows carry their own `.bordered` "Move to
Trash…" instead of a checkbox effect. Hands-off rows show the reason as their why line ("Listed only. Removing the
file would not stop a job that is already loaded."). The bottom bar on `barSurface()`: **`PlanText.moveButton`**
(`DuskButtonStyle`, disabled when nothing is ticked, `.keyboardShortcut(.defaultAction)`), "Select all High",
"Export report", "Cancel". Toolbar: Rescan (⌘R), History, Erase readiness, Preferences. "Not covered" as a final
disclosure listing `PlanText.notCovered()`. Keyboard: Full Keyboard Access reaches every row and checkbox; VoiceOver
label per row "Name, tier, size, reason" (BUILD_PLAN §8).

**Orphans preview**: the same screen with the header "These belong to apps I can't find. I may be wrong if the app
lives on a drive that is not connected." as the stage's 15pt line and the "Why might this be wrong?" disclosure under
it (a `.surface(16)` with the seven reasons as plain rows).

**Confirm sheet** (`ConfirmSheet`; sized to content, never a fixed height). `SheetHeader` style: "Move 14 items to
Trash?" 22pt; a `.surface(16)` with one row per class: symbol, class, "9 items · 412 MB" rounded; Medium items named
individually under a small-caps "May hold your data" header with the required `Toggle("I've looked at these; they
may contain my data.")`; the fixed line "Items go to the Trash. You can undo from History until you empty it." in
13pt secondary; Cancel (`role: .cancel`) and the `DuskButtonStyle` "Move 14 items to Trash" (disabled until the
acknowledgement when Medium is included). No violet panel, no red, no type-to-confirm.

**Running** (phase `.running`). The sheet stays; behind it the rows leave with `.transition(.outline(reduceMotion))`
as outcomes arrive (MOTION §3.2); a small `ProgressView` with "Moving… 6 of 14" in rounded digits. The only loop is
the system spinner. Demo freezes at 40 % (BUILD_PLAN §9).

**Result** (`ResultView`, a sheet over `Dawn()`). "Moved 14 items (212 MB) to Trash." at 22pt with the number in
rounded, then `PlanText.resultLine`'s second sentence in 13pt secondary ("Space is freed when you empty the Trash.
Local snapshots can keep it in use for a while longer."); a `.surface(16)` of moved rows with `checkmark.circle.fill`
in green; "Left alone" rows grouped by `TrashStatus.word` with `hand.raised` (plain, secondary) and failed rows with a
red `xmark.circle.fill` and the plain-English what-to-do; the **Trace Report card preview** (§6.6) lifted with
`HoverTilt(max: 4, glare: true)` (replaces the welcome tilt while the sheet is up: still ≤ 2 on screen); the action
bar on `barSurface()`: **Undo all** (`DuskButtonStyle`), "Open Trash", "Open History", "Copy card".

**History** (`HistoryView`). A plain `List` of runs newest first, each a `.surface(16)`: the date and `label` 15pt
semibold, "14 items · 212 MB" rounded, "Undo run" `.bordered` (disabled with "Already emptied" when nothing is
`inTrash`), then item rows (`TrashStatus`-style symbol by `HistoryState`: `arrow.uturn.backward.circle` restored,
`trash` in Trash, `minus.circle` emptied), each with its own "Undo". Under the list, in 12pt secondary: "Finder's Put
Back may not work for items moved by apps. Use Undo here." Toolbar: "Reveal log in Finder".

**Trace Report** (`TraceCardView` preview inside a sheet, app-report). Over `Dawn()`: the card at 600×315pt, lifted
(`lifted()`), `HoverTilt(max: 4, glare: true)`; under it `Toggle("Hide app names")` (pre-ticked for multi-app
reports), and the bar: "Copy as image" (`DuskButtonStyle`), "Save PNG…", "Save Markdown…", "Save JSON…". The
"Sample data" watermark is drawn on the card in demo mode (§6.6).

**Erase readiness** (`ReadinessView`). Over `Dawn()`: "Erase readiness" 28pt, "Read-only. Three system commands, no
changes." 13pt secondary; one `.surface(16)` of `ReadinessText.lines` as rows (a 6px dot in `tone.tint`, title 13pt
semibold, body 12pt secondary, "could not be read" rows set exactly like the others); a second `.surface(16)` titled
"Who could read old data" with `ReadinessText.threats()` as two-column rows (who; answer); `ReadinessText.notReachable`
as a plain 12pt line; "Need to be sure?" with a `Link` to `Links.eraseAllContent` ("Erase All Content and Settings")
set as a `.bordered` button. No violet panel, no switch, no number bigger than a row's.

**Preferences sheet** (`PreferencesSheet`). `Form` + `.formStyle(.grouped)`, stock: the keep-list (add by dropping an
app or typing a bundle ID; a removal only removes a user entry), "Hide app names in exports", "Show menu bar item",
"Check for updates" (opens Releases). No custom surfaces here.

**About** (`AboutView`). The icon on `OnFloor(height: 96)`, "Aftertaste 0.1.0" rounded, the honesty statement and the
not-affiliated line in 13pt secondary, links as `.link` buttons, "Copy diagnostics" (`CopyButton`).

**Edge states** (`EdgeStates`). All plain: a secondary sentence over `Dawn(strength: 0.5)` or a plain row. "Nothing
found. Looked in all 18 places." shows the green check at 36pt (`.bounce(on:)` once on macOS 14+) only when
`coverage.isComplete`; a partial scan shows "Nothing found in the 16 places I could read. 2 protected by macOS." with
no check. Journal-not-writable and Trash-unavailable are sheets with the fixed sentences and "Reveal folder". A
Needs-admin app row says "Needs your administrator. Drag it to the Trash in Finder, then run Find leftovers."

**Dark mode.** The sky wash; surfaces white .055 with a white .10 rim; violet text uses `Brand.duskInk`. Increase
Contrast gives the plain window, 1pt primary strokes, bar segments with a 1pt stroke and no violet edge.

### 6.6 Trace Report card (`TraceCardView`, app-report; the PNG; no materials, blur or shadows inside)

1200×630 at 2× from a 600×315pt view. The night sky in every scheme (the card is an object): `#0E0B1F` → `#141827`
top to bottom, the horizon as a 1pt teal line (`Brand.horizon` at .7) across the card at 82 % of its height with a
faint pool under it; the mark and "AFTERTASTE" (small caps, `#A3A8BA`) top-left; `TraceReportText.headline` at 44pt
display semibold `#EEF0F7` with the app name in `#B7A8FF`; `figures` at 22pt rounded with the numbers tabular;
`coverage` and `listedNote` at 17pt `#A3A8BA`; `provenance` at 13pt mono `#A3A8BA` bottom-left; the site address
bottom-right; the "Sample data" `Tag` top-right when `isSample`. Names replaced by "App 1", "App 2" when
`namesHidden`. `ImageRenderer` on macOS 13: VERIFY the 1200×630 output (BUILD_PLAN §12). The back of the card (the
footer sentence and "Not covered") exists only on the site and in the Markdown export; the PNG is the front.

## 7. Icon and social image (infra: `tools/make_icon.py`, `tools/make_og.py`, stdlib SDF renderers)

- **App icon:** a violet-black squircle (`#0E0B1F` → `#141827`, a faint top highlight) with the afterglow: a teal
  horizon line (`#7FE3D6`, core `#EFFFFC`) at 70 % of the height with a soft teal pool below and a violet haze above
  it; the **mark** in lilac (`#B7A8FF`): a rounded-square outline (dashed, 4 dashes per side, stroke 1/14 of its
  width) centred on the horizon, with its top-right corner missing and a small solid tile of the same corner radius
  set diagonally above the gap (the thing that left). Reads at 16px as "dark square, teal line, dashed square with a
  dot". No text, no vendor marks. Later, on a Mac: an Icon Composer `.icon` with three layers (sky, horizon, mark)
  and specular on the solid tile.
- **Menu bar:** the mark alone, template (§6.4).
- **OG image (1200×630):** the desk edge to edge (sky at the top, horizon, pool), the icon at 280px standing in the
  pool with its reflection, the wordmark under it. No sentence in the image; `og:title` carries "Aftertaste for Mac:
  find what an uninstalled app left behind, and why".

## 8. Acceptance and budgets

**Looks premium (a judge checks light and dark captures at 1440 and 390px, base and `prefers-contrast: more`,
against `refs/`):**

- [ ] The hero has no container edge: light comes only from the horizon; the desk reads as a desk; the outline stands
      where the app was, the five slabs step back in depth beside it, the tray sits at the desk's edge, the card is in
      front and the brightest object; everything is still after 2.6 s; pressing "Move 4 items to Trash" peels four
      slabs into the tray one by one, the Hands-off slab stays, the tray shows 4, the outline fades to a trace, the
      status says what happened; "Reset demo" brings them back; "Turn the card over" shows the footer sentence.
- [ ] Exactly one accent is visible (violet); teal appears only in the sky and the horizon; green only in dots, the
      Nothing-found check and moved rows' symbols; red only on a failed row's symbol; no tier gets a coloured panel;
      a Review row is set exactly like a High row apart from the chip word and the dot.
- [ ] Every raised surface shows a lit top edge, a 0.5px hairline (1px rim in dark) and an ink-tinted shadow; slabs
      cast a long violet-tinted shadow; buttons have a lip and no glow; key-caps sink on press.
- [ ] Headlines are the system display face at 600 with tight tracking; numerals are rounded and tabular; paths are
      mono; labels are small caps; nothing is ALL CAPS copy; no font file is requested (Network panel).
- [ ] Light mode is the same desk in daylight (cool paper, a pale afterglow), not a grey page; dark is cool near-black,
      never #000.
- [ ] Residue bars and slab labels never truncate: segments have a floor width and the legend carries the words;
      sheets are sized to their content; nothing clips at the largest text size.
- [ ] Real screens appear only at ≤ 50% of their pixel width; no horizontal page scroll at 360px.
- [ ] Reduce Motion, no-JS and print show the found state; print is dark text on white; both hero buttons swap
      instantly under Reduce Motion and are hidden without JS.
- [ ] Every page carries "Aftertaste is not affiliated with or endorsed by any app it detects." and no page, README or
      changelog line contains a banned phrase (`tools/safety_greps.sh` check 17 is green).
- [ ] `python tools/build_site.py --check` passes with exactly two `:root` blocks, no `style=""`, the CSP exact.
- [ ] App, from CI captures: the welcome's drop zone is the one lifted object on the sky wash with no grey-on-grey;
      the preview shows one layered group card per app with a residue bar whose legend names every class; tier chips
      carry words and only High has a violet dot; the confirm sheet names Medium items and holds the acknowledgement;
      the result shows Undo all as the one prominent button; the readiness panel has no red and no switch; the card
      has no app names when hidden and shows the watermark in demo mode; VoiceOver labels read "Name, tier, size,
      reason".

**Budgets:**

| Item | Cap |
|---|---|
| `site/static/styles.css` | 40 KB (`BUDGET` in `build_site.py`) |
| `site/static/motion.js` | 6 KB: the shared 2.7 KB plus the sweep job (MOTION §2.4), under 1 KB |
| Webfonts | 0 files, 0 bytes |
| Home HTML (built) | ≤ 36 KB |
| First load (HTML + CSS + JS + icon + favicon) | ≤ 110 KB |
| Lazy screenshots | ≤ 110 KB each, 4 per scheme, only the active scheme loads |
| Third-party requests, CDNs, trackers, network calls from the app | 0 |
| Hero sequence | ≤ 2.6 s, once; the peel ≤ 0.9 s on the button; the flip ≤ 0.6 s; ≤ 4 planes |
| CLS / LCP | 0 / the h1 text |
| App | CPU 0% within 2 s of any entrance; the outline fade ≤ 1 s for the whole list; `HoverTilt` ≤ 2 on screen; new assets or dependencies: none |
| CSP | the siblings' exact string; no inline script, style or handler |

**Security.** Nothing here touches the safety rules, `Trasher.swift`, `Journal.swift`, the entitlements or the data
flow. The card path stays effect-free. Materials and glass are system APIs. The site makes no request beyond its own
files. The design never shows a path the report would scrub (the `~` form only).

## 9. Changes for other owners, decisions for the lead, VERIFY list

**By owner (proposed, not made):**

- **site (`site/**`):** §2–§5 and MOTION §2; the inline glyph sprite (§4.3); the `html[lang]` media rules; the
  `color-scheme` and two `theme-color` metas; `motion.js` = the shared file plus the sweep job reading its status
  strings from `data-sweep-said` / `data-sweep-reset` (MOTION §2.4); the three guides' outlines (§5) with sources.
- **infra (`tools/build_site.py`, `make_icon.py`, `make_og.py`):** `BUDGET` with `motion.js` 6 000 and no `fonts/*`
  entry; fail `--check` if any `fonts/` file exists; the banned-phrase grep over `site/_dist`; the icon and OG per §7.
- **app-shell (`WelcomeView`, `FirstRunView`, `RootView`, `AboutView`):** §6.5's welcome, first run and about;
  `MenuBarIcon.glyph` for the optional item; `activateApp()` from Compat.
- **app-content:** §6.5's preview, orphans, confirm, running, result, history, readiness, preferences, edge states;
  `ResidueBar` fed from each group's items by `kind` and the ticked set; `.transition(.outline(reduceMotion))` on
  `ItemRow`.
- **app-report:** §6.6, using `Brand` and the card's fixed colours; nothing with a shadow inside the rendered view.
- **core (`Text`):** nothing new; `Format.bytes`, `Format.count`, the `PlanText` and `TraceReportText` lines are what
  the surfaces print. One request: `ReadinessText.Tone` is referenced as `ReadinessText.Tone` (BUILD_PLAN §4.8
  declares it inside `Line`; if it is nested as `Line.Tone`, the §6.1 extension targets that).
- **copy / lead (BUILD_PLAN §8):** the proof-strip numerals (§3 item 3); the FAQ questions; the 404 line; the hero
  h1 "What an app left behind."; the finale "See what's left. It's free."; the first-run "Never" line "nothing
  deleted: Trash only, with Undo"; `TrashStatus.word` strings (§6.1) if BUILD_PLAN wants them fixed.
- **BUILD_PLAN §8:** add "the site follows the system scheme; the dark palette is the designed-first one and the one on
  the OG image"; record the accent (`#A99BFF` button, `#5A44C4`/`#B7A8FF` as text) and that teal is sky only.

**Decisions for the lead:** (1) confirm the accent (dusk violet) and that teal never appears on a control; (2) confirm
two hero buttons (the peel and the flip; the flip reuses the shared job, the peel is the appended sweep job with
attribute-driven status text); (3) confirm `Tier.displayName` is the chip word and only High gets the violet dot;
(4) confirm the guide G2 title keeps the word "safe" (it is the search phrase) while the body avoids it.

**VERIFY (on a Mac or in Safari):** every SF Symbol in §6.1, §6.5 on macOS 13 (`square.stack.3d.up`,
`slider.horizontal.3`, `macwindow`, `play.square`, `square.on.square`, `app.dashed`, `app.badge.checkmark`,
`doc.text.magnifyingglass`, `person.badge.key`, `lock.shield`, `circle.dashed`, `arrow.uturn.backward.circle`,
`wifi.slash`, `hand.raised`); `Font.smallCaps()` with SF; `EllipticalGradient` on macOS 13; `Canvas` in
`ImageRenderer` for the menu bar glyph; `OnFloor`'s shadow offset; `HoverTilt` signs; the `Outline` transition's
removal timing with a per-row delay; `.contentTransition(.numericText())` while `finished` changes quickly;
`:has()` in the slab lit-edge rule on Firefox (fallback: a `.medium`/`.listed` class); `backface-visibility` on the
card's faces inside a `preserve-3d` parent in Safari; `-webkit-box-reflect` inside a 3D parent; `color-mix()` in the
`.tag` rules on Safari 16.2+; the JPEG corner radius at half scale; `screencapture -o -l` for the window.
