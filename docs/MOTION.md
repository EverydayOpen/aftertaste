# Motion spec: Aftertaste (website and app)

**Why:** the family requirement (2026-09-28): a modern UI with 3D motion that stays lightweight, on the website and
in the app. Aftertaste's version of it is "The Morning After" (`docs/DESIGN.md` §1): one scene, one peel, one fade,
then stillness.
**Authority:** this file is authoritative for motion. `docs/DESIGN.md` is authoritative for tokens, surfaces and
compositions and wins where the two conflict. BUILD_PLAN §8 already fixes the rules this file obeys: one signature
animation (the outline that fades, at most 1 s for the whole list), everything else a plain fade, all of it off under
Reduce Motion (the end state with at most a 150 ms fade), nothing moving at idle.
**Shared system:** §1 is the EverydayOpen motion language, copied verbatim from the Overstay repo's `docs/MOTION.md`
(identical there, in Tirekick's and in Whydunit's); change all four together. Where §1 says "Tirekick (macOS 13)",
read Aftertaste: the deployment target is the same. Two Aftertaste-specific differences to §1.7: there is no webfont,
and `site/static/motion.js` is the shared file **plus one appended job** (the sweep, §2.4, the same job as
Overstay's with its status strings read from attributes), so its cap is 6 KB, not 5.
**Status:** nothing in this file has been built or run. The CSS and JS in §2 follow the same mechanics as the
siblings' prototype-tested code but have not themselves been opened in a browser. The Swift in §3 is written, not
compiled; anything unconfirmed is marked VERIFY.

## 1. The EverydayOpen motion language (shared, identical in all four repos)

### 1.0 What makes 3D feel premium and still light (research, 2026-09-28)

- **Only the object moves.** Apple's product pages keep headlines, prices and buttons still. The product and the
  depth around it do the moving, and the hero plays once and then stops.
- **One camera, a few planes.** Linear and Raycast get depth from 2 to 4 flat layers at different Z, turned a few
  degrees in one perspective. They never build a full 3D model. Flat layers are cheap and keep text sharp.
- **Physical, damped, quick.** Things and Arc use short springs with a little overshoot for small objects and none
  for big surfaces. Nothing floats for more than about a second.
- **Light follows the pointer.** macOS Tahoe's Liquid Glass puts specular highlights where you move, and Reduce Motion
  turns that parallax off. Here that becomes glare under the pointer plus shadows that don't move.
- **The platform does the heavy lifting.** CSS 3D transforms and scroll-driven animations run on the compositor.
  Safari 26 shipped scroll-driven animations, and Safari 26.4 moved them to the compositor thread. Firefox stable
  still hides them behind a flag (mid-2026), so it gets a small IntersectionObserver fallback. In SwiftUI,
  `rotation3DEffect`, springs and transitions cover everything here without SceneKit or Metal.
- **Trust tools animate facts calmly.** Motion never makes a verdict look scarier or more cheerful than it is.

### 1.1 Principles (rules, not taste)

1. **Text never waits.** Hero headlines, taglines, verdicts, numbers and buttons render still, at once. Below the
   fold, a block can rise in as it enters the viewport, and it is done by the time 75% of it is visible.
2. **One hero moment per surface, then stillness.** Every sequence ends: at most 3.2 s on the web and 1 s in the
   apps. The only loops are a progress indicator that runs while real work runs (a scan, the checks).
3. **Motion never encodes severity.** A red "Walk away" arrives exactly like a green "Clean". Nothing shakes, flashes
   or pulses to alarm.
4. **Depth follows light.** A surface turns to face the pointer: the edge under the pointer recedes. The glare sits
   under the pointer. Shadows are fixed per layer and move only with their surface.
5. **Physical and quick.** Surfaces use springs with bounce ≤ 0.25. Small glyphs use ≤ 0.4. Nothing lasts longer
   than 1.1 s except the one-time hero sequence.
6. **Reduce Motion means no movement.** The end state is the same, reached by at most a 150–200 ms fade. No tilt, no
   parallax, no flip: a flip becomes a crossfade or an instant swap.
7. **Compositor only.** The web animates `transform`, `translate`, `rotate`, `scale` and `opacity`. The apps animate
   geometry effects and opacity, never frames or padding, during 3D motion.

### 1.2 Tokens

**Depth.** The web shares one real perspective per scene. SwiftUI has no shared 3D space, so each view gets its own
`perspective:` (1 is the default; lower is flatter). The table's mapping is approximate: VERIFY on a Mac and tune by
eye.

| Token | CSS | SwiftUI `perspective:` | Use |
|---|---|---|---|
| scene | `--persp-scene: 1600px` | 0.4–0.5 | hero scenes, grids, the report card, the laptop |
| card | `--persp-card: 900px` | 0.6 | cards, tiles, rows, FAQ answers |
| glyph | `perspective(400px)` inline | 1.0 (default) | icons, step numbers, keys |

| Z layer | CSS `translateZ` | SwiftUI stand-in | Shadow |
|---|---|---|---|
| back | −140 to −160px | smaller, behind in a ZStack | none |
| surface | 0 | the view itself | `--shadow` (z3) if it floats, none on a band |
| hug | +40 to +60px | offset ×1 of the tilt | `--z1`/`--z2` |
| float | +90px (max +140) | offset ×2 of the tilt | `--shadow` |

Use at most 4 layers in one scene.

**Easing and springs.**

| Token | CSS | SwiftUI (Whydunit, macOS 15) | SwiftUI (Tirekick, macOS 13) | Use |
|---|---|---|---|---|
| out | `--ease-out: cubic-bezier(.16, 1, .3, 1)` | `Motion.spring(_:)` = `.spring(duration: 0.45, bounce: 0.22)` | `.spring(response: 0.45, dampingFraction: 0.78)` | entrances, settling, tilt return, flips |
| hero | `--ease-out` over `--t-hero` | `Motion.hero` = `.spring(duration: 0.9, bounce: 0.2)` | `.spring(response: 0.9, dampingFraction: 0.8)` | one-time entrances (icon, lid) |
| spring | `--ease-spring: cubic-bezier(.34, 1.56, .64, 1)` | `Motion.pop` = `.spring(duration: 0.32, bounce: 0.38)` | `.spring(response: 0.32, dampingFraction: 0.62)` | chips, symbols, keys |
| follow | `var(--t-fast)` with `--ease-out` | `Motion.follow` = `.interactiveSpring(response: 0.25, dampingFraction: 0.86)` | same (macOS 10.15 API) | following the pointer |
| in-out | `--ease-in-out: cubic-bezier(.65, 0, .35, 1)` | `.easeInOut(duration:)` | same | beams, rising files |
| standard | none | `Motion.standard(_:)` (existing) | `Motion.standard(_:)` (existing) | plain state changes |

`.spring(duration:bounce:)` is macOS 14. With bounce ≥ 0 its damping fraction is 1 − bounce, so the Tirekick column
is the same curve.

**Durations.** `--t-fast .16s` (hover, press), `--t-base .32s` (state change, FAQ), `--t-slow .7s` (reveal, tilt
settle), `--t-hero 1.1s` (hero plane). **Stagger:** 90 ms between cards and 80 ms between report rows on the web.
In the apps, Whydunit rows use `Motion.stagger = 0.045` and Tirekick check rows keep their existing 70 ms. The
stagger index is capped (6 on the web, 8 in the apps), so a long list never trickles.

### 1.3 Hover tilt, glare and sheen

| Surface | Max tilt | Lift | Glare |
|---|---|---|---|
| Hero scene (window, laptop and card together) | 5° | none (it already floats) | only the report card |
| Cards and tiles | 7° | `scale 1.02` (web), press `0.97` | web yes, app no |
| App icon (Whydunit Welcome) | 12° | none | yes, masked to the icon |
| Laptop drawing (Tirekick Welcome) | 8° | none | no |
| Reading surface with long text (report card in the app) | 4° | none | yes |
| Tables, forms, lists, sidebars, buttons, navigation, keys | 0° | press depth only | no |

- **Direction.** `px` and `py` run from −1 to 1, measured from the center. CSS uses
  `rotateX(py × −max) rotateY(px × max)`, which was checked in Chromium: the edge under the pointer recedes. SwiftUI
  starts from the same formula; VERIFY the signs on a Mac.
- **Follow fast, settle slow.** Follow the pointer over 160 ms. Return over 700 ms (web) or with `Motion.spring`
  (app).
- **Fine pointers only.** Tilt needs `(hover: hover) and (pointer: fine)`; a Mac always qualifies. Phones get
  scroll-driven depth instead (§1.7).
- **Hit areas never move.** The web reads the pointer on the element and caches the box when the pointer enters. The
  app gets `onContinuousHover` coordinates in the untransformed layout frame.
- **Glare** is a soft radial spot under the pointer, about 60% of the surface wide, fading in over 160 ms. White
  can't shine on white, so light mode uses a faint accent spotlight (`rgb(0 102 204 / .07)`). Dark mode uses white
  at .10, and the app uses white at .28. On the web it is a 200% layer moved with `transform` and clipped by the
  card, drawn between the card's fill and its text, so it never repaints and never lowers text contrast.
- **Sheen** is a single linear highlight sweep. It is used only for the Tirekick scan beam, once.

### 1.4 Shadows that sell depth

- `--z1: 0 1px 2px rgb(0 0 0 / .06), 0 4px 12px rgb(0 0 0 / .05)`: hug layers and guide boxes.
- `--z2: 0 2px 6px rgb(0 0 0 / .06), 0 12px 32px rgb(0 0 0 / .1)`: small floating badges.
- `--shadow` (existing, z3): floating surfaces and chips.
- **Dark mode:** black backgrounds swallow shadows, so each shadow is darker and carries a 1px light rim
  (`0 0 0 1px rgb(255 255 255 / .06–.12)`) that draws the edge.
- **Never animate `box-shadow` or `filter`.** A shadow belongs to its layer. Depth changes come from moving the
  surface, and the shadow moves with it.
- **App:** use `.compositingGroup().shadow(...)` on anything that contains text, so glyphs don't get shadows of
  their own.

### 1.5 Reduce Motion

| Effect | With Reduce Motion |
|---|---|
| Hero sequence (web) | Nothing plays. The page shows the final state: lid open, files uploaded, rows filled, chips gone. |
| Pointer tilt, glare, parallax | Off (flat). |
| Scroll reveal, steps coin, phone scroll lean | Off: content is simply there. |
| FAQ unfold, button press scale | Off. `<details>` opens instantly. |
| Report card flip (web) | Instant swap by `visibility`. The button still works. |
| App entrances (icon, lid, card deal-in) | Shown at rest immediately, or a `Motion.standard(true)` fade. |
| Row flip-ins, split-flap verdict, sheet card swaps | `.opacity` transitions. |
| Scan loops (cloud glyph, laptop beam) | Not drawn. The system `ProgressView` stays. |
| Symbol effects | Removed (`.symbolEffectsRemoved(reduceMotion)` in Whydunit; Tirekick never triggers them). |

The web puts every movement inside `@media (prefers-reduced-motion: no-preference)`, so Reduce Motion needs no
override rules except the flip. The apps read `@Environment(\.accessibilityReduceMotion)` in every view that moves,
or go through `Motion.*(reduceMotion)`. VoiceOver labels, traits and element grouping never change.

### 1.6 Performance rules

**Web**

- Animate `transform`, `translate`, `rotate`, `scale` and `opacity`, plus the custom properties `--px` and `--py`
  that feed them. Never animate `box-shadow`, `filter`, `background-position`, size or position.
- **Grouping properties flatten 3D.** Never put `opacity < 1`, a non-visible `overflow`, `filter`, `clip-path`,
  `mask`, `mix-blend-mode`, `isolation` or `contain: paint` on an element that has
  `transform-style: preserve-3d`. Fade its children or its parent instead. The prototype follows this.
- No `backdrop-filter` inside a 3D scene (Safari draws it flat), and no permanent `will-change`: it wastes GPU memory
  and blurs text in Safari.
- Use `translate`/`rotate`/`scale` (the individual properties) for reveals and `transform` for tilt, so both can
  run on one card without fighting.
- At most one `requestAnimationFrame` per frame. `pointermove` listeners are passive. The box is read once per
  element entered.
- No infinite animations on the web.
- **CSS stays in `styles.css`.** `motion.js` is byte-identical in both repos (2.7 KB; hard cap 5 KB) and loads with
  `defer` from `layout.html`.
- **Two `:root` blocks only.** `tools/build_site.py` `contrast()` unpacks exactly two `:root { }` blocks, light then
  dark; a third one crashes `--check`. New tokens go into the existing two blocks. Any other override uses `html`
  or a class.
- `data-theme` and `localStorage` fail `--check`. Dark and light come from `prefers-color-scheme` only.

**Apps**

- **Zero CPU when idle.** Springs settle and stop. `repeatForever`, a `phaseAnimator` without a trigger, and
  `TimelineView` appear only inside views that exist only while work runs: Whydunit's first-scan view and Tirekick's
  "Checking this Mac…" view.
- Use only `.animation(_:value:)`, never unscoped `.animation`. Call `withAnimation` only in event handlers and
  `onAppear`.
- **3D on content only.** Never add 3D to a `Table` or `List` row container: AppKit owns the cell, its clipping and
  its selection.
- `ImageRenderer` paths get no effects inside the rendered view. Tirekick's `ReportCardView` is the PNG.
- No `drawingGroup()` over text: it rasterizes, and the text blurs at 3D angles.
- Hover state lives in the modifier (`@State`), never in `AppStore` or `AppModel`. Keep at most 8 `HoverTilt`
  views on screen at once; plain `onHover` rows are cheap and don't count.
- Written, not compiled: none of the Swift in this file has been built. Mark every API you can't confirm with
  `VERIFY`.

### 1.7 Shared web code (prototype-tested in Chromium on Windows, 2026-09-28)

**Tokens.** Append these to the **existing** light `:root` block:

```css
  /* Motion and depth (docs/MOTION.md §1). Only these two :root blocks: build_site.py contrast() reads exactly two. */
  --ease-out: cubic-bezier(.16, 1, .3, 1);
  --ease-spring: cubic-bezier(.34, 1.56, .64, 1);
  --ease-in-out: cubic-bezier(.65, 0, .35, 1);
  --t-fast: .16s;
  --t-base: .32s;
  --t-slow: .7s;
  --t-hero: 1.1s;
  --persp-scene: 1600px;
  --persp-card: 900px;
  --z1: 0 1px 2px rgb(0 0 0 / .06), 0 4px 12px rgb(0 0 0 / .05);
  --z2: 0 2px 6px rgb(0 0 0 / .06), 0 12px 32px rgb(0 0 0 / .1);
  --glare: rgb(0 102 204 / .07);   /* white can't shine on white: a faint accent spotlight instead */
```

Then append these to the existing dark `:root` block:

```css
    --z1: 0 0 0 1px rgb(255 255 255 / .06), 0 4px 12px rgb(0 0 0 / .5);
    --z2: 0 0 0 1px rgb(255 255 255 / .08), 0 12px 32px rgb(0 0 0 / .6);
    --glare: rgb(255 255 255 / .1);
```

**Shared rules.** Append these to `styles.css`, and delete the old
`@media (prefers-reduced-motion: no-preference) { .button { transition: background-color .2s; } }` line, which the
button rule below replaces. The block adds about 3 KB.

```css
/* Motion (docs/MOTION.md). Everything above is the finished, still page; movement only under no-preference.
   Animate transform, translate, rotate, scale and opacity only. Never opacity, overflow, filter or clip-path on a
   transform-style: preserve-3d element: they flatten its 3D. */
[data-tilt] { --px: 0; --py: 0; }
.stage { --tilt: 5deg; perspective: var(--persp-scene); }
.scene { position: relative; transform-style: preserve-3d; }
.grid { perspective: var(--persp-scene); }
.card[data-tilt] { --tilt: 7deg; position: relative; isolation: isolate; overflow: hidden; }
/* Glare: a 200% spotlight moved by transform (no repaint), between the card's fill and its text. */
.card[data-tilt]::after {
  content: ""; position: absolute; z-index: -1; inset: -50%; pointer-events: none; opacity: 0;
  background: radial-gradient(circle, var(--glare), transparent 30%);
  transform: translate(calc(var(--px) * 25%), calc(var(--py) * 25%));
}
@media (prefers-reduced-motion: no-preference) and (hover: hover) and (pointer: fine) {
  .scene, .card[data-tilt] {
    transform: rotateX(calc(var(--py) * var(--tilt) * -1)) rotateY(calc(var(--px) * var(--tilt)));
    transition: transform var(--t-slow) var(--ease-out), scale var(--t-base) var(--ease-out);
  }
  .tilting .scene, .card.tilting { transition-duration: var(--t-fast), var(--t-base); }   /* follow fast, settle slow */
  .card.tilting { scale: 1.02; }
  .card[data-tilt]::after { transition: opacity var(--t-base), transform var(--t-fast) linear; }
  .card.tilting::after { opacity: 1; }
}
/* Phones: no pointer, so the hero leans back and straightens as it scrolls into place. */
@media (prefers-reduced-motion: no-preference) and (hover: none) {
  @supports (animation-timeline: view()) {
    .scene { animation: settle linear both; animation-timeline: view(); animation-range: cover 0% cover 45%; }
  }
}
/* Reveal: scroll-driven where supported; motion.js adds .reveal-io and .in elsewhere. */
@media (prefers-reduced-motion: no-preference) {
  @supports (animation-timeline: view()) {
    .reveal { animation: rise linear both; animation-timeline: view(); animation-range: entry 0% entry 75%; }
  }
  .reveal-io .reveal:not(.in) { opacity: 0; }
  .reveal-io .reveal.in { animation: rise var(--t-slow) var(--ease-out) calc(var(--i, 0) * 90ms) backwards; }
  details[open] > p { animation: unfold var(--t-base) var(--ease-out); }
  summary::after { transition: rotate var(--t-base) var(--ease-out); }
  details[open] summary::after { rotate: 180deg; }
  .button { transition: background-color .2s, scale var(--t-fast) var(--ease-out); }
  .button:active { scale: .97; }
}
details { perspective: var(--persp-card); }
@keyframes settle { from { transform: rotateX(12deg) scale(.96); } }
@keyframes rise { from { opacity: 0; translate: 0 32px; rotate: x 10deg; } }
@keyframes unfold { from { opacity: 0; translate: 0 -6px; rotate: x -12deg; } }
@keyframes fade { from { opacity: 0; } }
@keyframes pop { from { opacity: 0; transform: translateZ(0) scale(.8); } }
```

**`site/static/motion.js`** is byte-identical in both repos and loads from `layout.html` right after the stylesheet
link: `<script src="/motion.js" defer></script>`. The build prefixes `src="/`, and `--check` confirms the file
exists. It has three jobs:

1. **Tilt.** Write `--px`/`--py` on the hovered `[data-tilt]` element and toggle `.tilting`. This happens only for
   a mouse, without Reduce Motion, throttled to one rAF per frame. It resets on scroll and when the pointer leaves
   the window.
2. **Reveal fallback.** Where `animation-timeline: view()` is unsupported (Firefox stable), add `.reveal-io` to
   `<html>` and give `.in` to each `.reveal` as it enters, staggered within each batch. Anything already on screen at
   load gets `.in` before the class goes on, so it never flashes.
3. **Flip.** Unhide each `[data-flip]` button and make it toggle `.flipped` on its `aria-controls` target, keeping
   `aria-pressed` in sync.

With no JS, the pages are complete and still. Hero sequences are pure CSS and need no JS.

```js
// Motion for the EverydayOpen sites (docs/MOTION.md). Every page is complete and static without it.
(() => {
  const root = document.documentElement;
  const calm = matchMedia('(prefers-reduced-motion: reduce)');
  const fine = matchMedia('(hover: hover) and (pointer: fine)');

  // Tilt: --px/--py (-1..1 from the center) on the hovered [data-tilt]; CSS turns them into rotation and glare.
  // The box is read once per element entered, so the tilt never feeds back into it.
  let el = null, box, x = 0, y = 0, frame = 0;
  const enter = (t) => {
    if (el) {
      el.classList.remove('tilting');
      el.style.removeProperty('--px');
      el.style.removeProperty('--py');
    }
    el = t;
    if (el) {
      el.classList.add('tilting');
      box = el.getBoundingClientRect();
    }
  };
  const unit = (v, start, size) => Math.max(-1, Math.min(1, (v - start) / size * 2 - 1)).toFixed(3);
  const draw = () => {
    frame = 0;
    if (!el) return;
    el.style.setProperty('--px', unit(x, box.left, box.width));
    el.style.setProperty('--py', unit(y, box.top, box.height));
  };
  addEventListener('pointermove', (e) => {
    if (e.pointerType !== 'mouse' || calm.matches || !fine.matches) return;
    const t = e.target.closest ? e.target.closest('[data-tilt]') : null;
    if (t !== el) enter(t);
    x = e.clientX;
    y = e.clientY;
    if (el && !frame) frame = requestAnimationFrame(draw);
  }, { passive: true });
  addEventListener('scroll', () => el && enter(null), { passive: true });
  root.addEventListener('pointerleave', () => enter(null));

  // Reveal, where CSS scroll-driven animations don't exist yet (Firefox): .in when it enters, staggered per batch.
  const items = document.querySelectorAll('.reveal');
  if (items.length && !calm.matches && !CSS.supports('animation-timeline: view()') && 'IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      entries.filter((e) => e.isIntersecting).forEach((e, n) => {
        e.target.style.setProperty('--i', Math.min(n, 6));
        e.target.classList.add('in');
        io.unobserve(e.target);
      });
    }, { rootMargin: '0px 0px -8% 0px' });
    items.forEach((e) => (e.getBoundingClientRect().top < innerHeight ? e.classList.add('in') : io.observe(e)));
    root.classList.add('reveal-io');
  }

  // Flip: a [data-flip] button turns the card named by aria-controls over and back.
  document.querySelectorAll('[data-flip]').forEach((b) => {
    const card = document.getElementById(b.getAttribute('aria-controls'));
    if (!card) return;
    b.hidden = false;
    b.addEventListener('click', () => b.setAttribute('aria-pressed', card.classList.toggle('flipped')));
  });
})();
```

### 1.8 Shared SwiftUI code (PROPOSAL, written, not compiled)

Both apps get the same pointer tilt, in `App/DesignSystem/Tokens.swift`. It uses only macOS 13 APIs:
`onContinuousHover` is macOS 13, and `rotation3DEffect`, `RadialGradient` and `mask` are older. **Whydunit** (macOS
15) replaces the `.background(GeometryReader …)` line with
`.onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }`, which avoids the one-argument `onChange`
that is deprecated from macOS 14.

```swift
/// Turns a surface to face the pointer (the edge under it recedes), at most `max` degrees, with an optional glare
/// masked to the content's own shape. Flat under Reduce Motion. The pointer is read in the layout frame, so the
/// tilt never moves hit areas.
struct HoverTilt: ViewModifier {
    var max = 7.0
    var glare = false
    @State private var size = CGSize.zero
    @State private var p = CGPoint.zero          // -1...1 from the center
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if glare && hovering {
                    RadialGradient(colors: [.white.opacity(0.28), .clear], center: .center,
                                   startRadius: 0, endRadius: size.width * 0.6)
                        .offset(x: p.x * size.width / 2, y: p.y * size.height / 2)
                        .mask { content }            // VERIFY: content drawn twice; fine for an icon and one card
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            // VERIFY on a Mac: the edge under the pointer should recede; negate both angles if it rises instead.
            .rotation3DEffect(.degrees(-p.y * max), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(p.x * max), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .background(GeometryReader { g in
                Color.clear.onAppear { size = g.size }.onChange(of: g.size) { size = $0 }
            })
            .onContinuousHover { phase in
                guard !reduceMotion, size.width > 0, size.height > 0 else { return }
                switch phase {
                case .active(let at):
                    withAnimation(Motion.follow) {
                        hovering = true
                        p = CGPoint(x: at.x / size.width * 2 - 1, y: at.y / size.height * 2 - 1)
                    }
                case .ended:
                    withAnimation(Motion.spring(false)) {
                        hovering = false
                        p = .zero
                    }
                }
            }
    }
}
```

The `Motion` additions (`spring`, `hero`, `pop`, `follow`) are in each app's section, spelled for its deployment
target.

**Sources:** WebKit, "WebKit Features in Safari 26.0" (webkit.org/blog/17333) and "WebKit Features for Safari
26.4" (webkit.org/blog/17862); Firefox's `layout.css.scroll-driven-animations.enabled` flag status (mid-2026
developer guides); Apple docs for `onContinuousHover(coordinateSpace:perform:)` (macOS 13) and
`rotation3DEffect(_:axis:anchor:anchorZ:perspective:)`; SF Symbols 6 effects `wiggle`, `breathe` and `rotate`
(macOS 15; WWDC24 "What's new in SwiftUI"). `keyframeAnimator` is deliberately unused. Nobody has checked whether a
one-shot run rests on the last keyframe or on `initialValue`, and plain `@State` plus a spring does the same job on
every macOS version without that question.

## 2. Aftertaste website

### 2.1 The story in 2.6 seconds, the peel and the flip

The desk is still dark. The horizon lights: a thin teal line far back, and its glow pools on the desk. An app icon
stands on the desk. It lifts away, up and toward the camera, and fades; where it stood a dashed outline remains.
Beneath the outline, one by one, five layers slide out and step back in depth beside it: Caches, Settings, Saved
state, Your data, Launch agents. The Trash tray settles at the desk's edge. The Trace Report card deals in at the
front right. Then the page is still: the pointer tilts the scene up to 5°, which parallaxes the slabs against the
outline and the card against the desk.

Press **Move 4 items to Trash**. The four ticked-or-tickable layers peel off the stack one after another, each
lifting from its top edge, sliding toward the tray and shrinking into it; the Hands-off layer stays where it is and
keeps its "Hands off" chip. The tray's count reads 4. The outline fades to a trace. The button reads **Reset demo**
and puts everything back. Press **Turn the card over** and the card turns on its vertical axis to show its back: the
footer sentence and "Not covered". The headline, lede and both page buttons never move.

| t (s) | What happens | Element | Easing |
|---|---|---|---|
| 0.00–0.50 | The horizon lights (`scaleX 0 → 1` from its middle; its glow comes with it) | `.horizon` | `--ease-out` |
| 0.10–0.80 | The desk and its pool fade in (opacity on a flat plane) | `.desk` | `--ease-out` |
| 0.30–1.20 | The icon lifts away: from standing (`translate3d(0,0,0) scale(1)`, opacity 1) to gone (`translate3d(0,-140px,140px) scale(.9)`, opacity 0) | `.appicon` | `--ease-in-out` |
| 0.70–1.00 | The outline draws in (opacity 0 → .55) | `.outline` | `--ease-out` |
| 0.90–2.00 | The layers slide out from under the outline's footprint to their stepped places, 110 ms apart | `.slabs li` | `--ease-out` |
| 1.70–2.10 | The tray settles (`translateZ(40px) scale(.96) → scale(1)`) | `.tray` | `--ease-spring` |
| 1.90–2.60 | The card deals in (`translate3d(0,-14px,80px) scale(.98)` → rest), its face fades in | `.report-wrap`, `.report` | `--ease-out` |

**The peel** (0.9 s, on the move button; reversible):

| t (s) | What happens | Element | Easing |
|---|---|---|---|
| 0.00–0.75 | Each peelable layer lifts from its top edge (`rotateX(-18deg)`), slides toward the tray and shrinks (`scale(.55)`), 90 ms apart (4 layers, so the last starts at 0.27 s and is gone by 0.9 s); its opacity fades over the last 0.3 s | `.swept .slabs li:not(.listed)` | `--ease-in-out` |
| 0.30–0.70 | The tray's count fades in; the tray's rim turns violet (a `background-color` transition on the `::before` lit edge, allowed: not a shadow or filter) | `.swept .tray` | `--ease-out` |
| 0.40–0.80 | The outline fades from .55 to .22 (the trace) | `.swept .outline` | `--ease-out` |
| 0.00–0.30 | The Hands-off layer moves 0 px; its chip stays | `.slabs .listed` | none |

**The flip** (0.6 s, on the card button; the shared `data-flip` job): `.report` rotates `0 → 180deg` on Y under
`--ease-out`; the faces are `backface-visibility: hidden`, so nothing is drawn twice. Reduce Motion swaps the faces
by `visibility` instantly (§1.5).

Reset reverses every transition over the same durations: the layers come back from the tray to their steps. The
label says "Reset demo", not "Undo", because the page must not pretend the demo did anything to a Mac.

### 2.2 DOM

The hero DOM is in DESIGN §4.2. The only motion-related attributes: `id="hero-scene"` on `.scene` (the move button's
`aria-controls`), `data-sweep="Reset demo"` with `data-sweep-said` and `data-sweep-reset` (the live-region strings),
`id="hero-card"` on `.report` (the flip button's `aria-controls`), and the `.sr-only[data-sweep-status]` live region
beside the move button.

Every `.card` in the pairing, FAQ and download-step sections: `class="card reveal" data-tilt`. The slab column in "To
the Trash, with Undo": `class="slabs reveal" data-tilt`. The ledgers, the proof strip, the FAQ panel, the threat
table and the filmstrip: `reveal` only, no tilt. `layout.html`: `<script src="/motion.js" defer></script>` after the
stylesheet link.

### 2.3 CSS (append after the shared block in §1.7; about 3.4 KB)

The rest state is written first (DESIGN §4.2); everything below is movement under `no-preference`, plus the peel's
and the flip's state rules, which apply with or without motion so the buttons still swap states.

```css
/* Hero (MOTION.md §2): the horizon lights, the icon lifts away, the outline draws in, the layers step out, the tray
   settles, the card deals in. Opacity sits on flat elements only: .desk, .appicon, .outline, .slabs li, .tray .count,
   .report .face (never on .scene, .stack, .slabs or .report-wrap, which are preserve-3d or hold a 3D child). */
@media (prefers-reduced-motion: no-preference) {
  .horizon { animation: horizon .5s var(--ease-out) backwards; transform-origin: 50% 50%; }
  .desk { animation: fade .7s var(--ease-out) .1s backwards; }
  .appicon { animation: leave .9s var(--ease-in-out) .3s backwards; }
  .outline { animation: fade .3s var(--ease-out) .7s backwards; }
  .slabs li { animation: step .8s var(--ease-out) backwards; }
  .slabs li:nth-child(1) { animation-delay: .90s; } .slabs li:nth-child(2) { animation-delay: 1.01s; } .slabs li:nth-child(3) { animation-delay: 1.12s; }
  .slabs li:nth-child(4) { animation-delay: 1.23s; } .slabs li:nth-child(5) { animation-delay: 1.34s; }
  .tray { animation: settle-tray .4s var(--ease-spring) 1.7s backwards; }
  .report-wrap { animation: deal .7s var(--ease-out) 1.9s backwards; }
  .report .face { animation: fade .5s var(--ease-out) 1.9s backwards; }
  /* The peel's transitions. */
  .slabs li { transition: transform .75s var(--ease-in-out), opacity .3s var(--ease-out) .45s; }
  .swept .slabs li:nth-child(2) { transition-delay: .09s, .54s; } .swept .slabs li:nth-child(3) { transition-delay: .18s, .63s; } .swept .slabs li:nth-child(4) { transition-delay: .27s, .72s; }
  .tray .count { transition: opacity .4s var(--ease-out) .3s; }
  .tray::before { transition: background-color .4s var(--ease-out) .3s; }
  .outline { transition: opacity .4s var(--ease-out) .4s; }
  /* The flip. */
  .report { transition: transform .6s var(--ease-out); }
}
/* The swept state (rest state of the peel; applies with or without motion). The transform keeps the rest function list
   in the same order and appends to it, so every engine interpolates per function (never a matrix decomposition). */
.swept .slabs li:not(.listed) { transform: translate3d(var(--dx), var(--dy), var(--dz)) scale(.55) translate3d(420px, 90px, 40px) rotateX(-18deg); opacity: 0; }
.tray::before { content: ""; position: absolute; inset: 0 var(--r-m) auto; height: 2px; border-radius: 1px; background: var(--hi); }
.swept .tray::before { background: var(--violet); }
.swept .tray .count { opacity: 1; }
.swept .outline { opacity: .22; }
/* The flipped state. */
.report.flipped { transform: rotateY(180deg); }
@keyframes horizon { from { transform: translateZ(-220px) scaleX(0); } }
@keyframes leave { from { opacity: 1; transform: translate3d(0, 0, 0) scale(1); } }
@keyframes step { from { opacity: 0; transform: translate3d(-150px, 40px, 0) scale(.96); } }
@keyframes settle-tray { from { transform: translateZ(40px) scale(.96); } }
@keyframes deal { from { transform: translate3d(0, -14px, 80px) scale(.98); } }
```

Notes:

- **The icon's rest transform is "gone"** (DESIGN §4.2 `.appicon`), so Reduce Motion, print and no-JS show the found
  state: an outline with nothing in it, the layers beside it. The `leave` keyframe only supplies the `from`.
- **Custom properties inside keyframes.** `step` ends at each slab's own `--dx/--dy/--dz` rest transform (the `to`
  is the element's computed value), so one keyframe serves five slabs. VERIFY in Firefox (expected fine since
  Firefox 57).
- **Per-function interpolation.** The rest transform `translate3d(var(--dx), var(--dy), var(--dz)) scale(1)` and the
  swept transform start with the same functions in the same order, so the browser interpolates each function rather
  than decomposing a matrix (which would spin the slab). Never reorder them. The appended `translate3d … rotateX`
  interpolate from identity.
- **`.report` rotates, `.report-wrap` does not:** the wrap holds the `translateZ(80px)` plane and the card's own
  `perspective`, so the flip never fights the scene tilt (§1.6: individual properties for reveals, `transform` for
  the tilt; here the card's `transform` is the flip and the tilt lives on `.scene`).
- **Reduce Motion:** every animation is inside `no-preference`; the `.swept` and `.flipped` rules are outside it,
  so both buttons still swap states, instantly.
- **The tray's `background-color` transition** on its `::before` is the one colour transition on the page. It is
  not a shadow or filter (§1.6), and it is a state swap, not an idle effect.
- **At ≤ 900px** the tray and the card are hidden (DESIGN §4.2), so the peel is the layers and the outline only. There
  is no horizontal scroll.

### 2.4 `motion.js`: the shared file plus the sweep

`site/static/motion.js` is the shared §1.7 script with this fourth job appended before the closing `})();` (about
600 bytes; the file stays under 6 KB). It is Overstay's sweep job with the two status strings read from attributes
instead of being written into the script, so the file carries no product copy. With no JS the hero is complete and
still in the found state and both buttons stay hidden (the flip job is already in the shared file).

```js
  // Sweep: the hero's move button peels the layers into the tray; the same button resets the demo.
  document.querySelectorAll('[data-sweep]').forEach((b) => {
    const scene = document.getElementById(b.getAttribute('aria-controls'));
    if (!scene) return;
    const move = b.textContent, reset = b.getAttribute('data-sweep');
    const say = b.parentNode.querySelector('[data-sweep-status]');
    b.hidden = false;
    b.addEventListener('click', () => {
      const on = scene.classList.toggle('swept');
      b.setAttribute('aria-pressed', on);
      b.textContent = on ? reset : move;
      if (say) say.textContent = on ? b.getAttribute('data-sweep-said') : b.getAttribute('data-sweep-reset');
    });
  });
```

The button is a real `<button>` with `aria-pressed`, hidden until JS runs, placed under the slab column so showing it
moves nothing. Hover never peels (people move the mouse over the layers to read them; the Tirekick §4.4 argument
applies unchanged). Proposal to Overstay (not made here): adopt the attribute-driven strings so the two files become
byte-identical again.

### 2.5 Sections and sub-pages

| Section | Motion |
|---|---|
| Hero text, lede, both buttons, trust line | none (LCP: the h1) |
| Hero scene | §2.1 once, then tilt 5° (fine pointers) or scroll lean (phones); the peel and the flip on their buttons |
| Pairing (Finder column vs the group card), FAQ, download steps | reveal plus 7° tilt, glare and scale 1.02 on the `.card`s |
| To the Trash, with Undo (the slab column) | reveal; 5° tilt on the whole column; slabs never move individually (the peel belongs to the hero) |
| What no app can erase (the threat table) | reveal only: facts stay still |
| Proof strip, ledgers, receipts, residue bars, filmstrip | reveal only (text and data stay still) |
| FAQ | answer unfolds; "+" turns into "×" |
| Buttons | press sinks 1px, shadow swapped |
| Finale | the icon on the desk with its reflection; `data-tilt` 8° on the icon only |
| What it reads, how it decides, guides, changelog, 404, llms.txt | no motion beyond reveal and the `--z1` shadow on `pre` and `.summary`; they print |

## 3. Aftertaste app (macOS 13 deployment, SwiftUI; written, not compiled)

BUILD_PLAN §8: one signature animation (the outline that fades), everything else a plain fade, all off under Reduce
Motion, nothing moving at idle. This section says exactly where each of those lives. Every API is macOS 13 unless it
sits in `App/DesignSystem/Compat.swift` behind `if #available`.

### 3.1 Tokens (`App/DesignSystem/Tokens.swift`)

Tirekick's `Motion` (`standard`, `spring`, `hero`, `pop`, `follow`), `HoverTilt`, `AnyTransition.flip` and
`FlipFaces` verbatim (§1.8, Tirekick MOTION §5.1), plus one constant:

```swift
extension Motion {
    /// Stagger between rows leaving for the Trash and between rows flipping in. Capped at index 8, so a long list never trickles.
    static let stagger = 0.045
}
```

### 3.2 The fade: the one signature animation

`AppModel.phase == .running(plan, finished:)` drives it. `finished` is the number of `ItemOutcome`s reported so far;
the plan's items are in execution order. The preview derives which rows have left:

```swift
/// A row leaves when its outcome has been reported as moved. Rows whose outcome is anything else stay, and the result
/// sheet says why. Honest timing: rows leave as outcomes arrive, never on a fake schedule.
func departed(_ plan: TrashPlan, finished: Int, moved: (String) -> Bool) -> Set<String> {
    Set(plan.items.prefix(finished).map(\.id).filter(moved))
}
```

`ItemRow` is inside a `ForEach` over the group's items minus `departed`; each row carries
`.transition(.outline(reduceMotion).animation(Motion.spring(reduceMotion).delay(reduceMotion ? 0 : Double(min(i, 8)) * Motion.stagger)))`
(DESIGN §6.3): the content fades in the first 30 % of the run, the dashed violet outline of the row's box rises and
then fades over the rest. The container's change is animated with `.animation(Motion.spring(reduceMotion), value:
departed)` so the remaining rows close the gap with a spring once the trace is gone. Fourteen rows leave inside
0.36 s of stagger plus a 0.6 s fade: under 1 s after the last outcome. Under Reduce Motion: `.opacity`, a 150 ms
linear fade, no delay, no outline. After `.result`, the rescan replaces the groups; rows that are gone are gone, and
the residue bar's segments re-lay out with `Motion.spring` (a `.animation(_:value:)` on the segments' bytes).

The `Metric("Selected", …)` above the groups counts down with `.contentTransition(.numericText())` (macOS 13) under
`.animation(Motion.standard(reduceMotion), value: finished)`: it shows the bytes still to be reported, not a promise
of what was moved. The result sheet shows the real outcome.

### 3.3 The card turns over

`TraceCardView`'s preview on the result and Trace Report sheets is dealt once with `FlipFaces(angle: dealt ? 0 : 180,
back: CardBack())` under `Motion.spring`, where `CardBack` is the night sky with the mark and no text (nothing to read
or miss while it turns); `dealt` flips to true in `onAppear` after 0.1 s. Then `HoverTilt(max: 4, glare: true)`. The
rendered PNG never includes the deal, the tilt or the glare: decoration sits outside `TraceCardView` (§1.6).

### 3.4 Entrances (one per screen, then stillness)

| Screen | Entrance | Length |
|---|---|---|
| Welcome | the drop zone's generic tile rises 16pt and fades in on `OnFloor`, `Motion.hero` after 0.1 s; then `HoverTilt(max: 6, glare: true)` on the drop zone | ≤ 1 s |
| First run | the icon rises 24pt and fades in on `OnFloor`, `Motion.hero` after 0.1 s; then `HoverTilt(max: 8, glare: true)` | ≤ 1 s |
| Preview | each group card appears with `.transition(.flip(reduceMotion))` on the 45 ms stagger (cap 3: at most three cards), once per scan result (`.id(scan.scannedAt)`); the sidebar rows are a system `List` and get no transition; rows inside a card get none (the card carried them in) | ≤ 0.6 s |
| Orphans preview | the same as Preview; the "Why might this be wrong?" disclosure opens with the system's motion only | ≤ 0.6 s |
| Confirm sheet | the system sheet animation only | system |
| Result, Trace Report | the card deal (§3.3), once per sheet | ≤ 0.5 s |
| History, Erase readiness, Preferences, About, edge states | none | 0 |
| Nothing found | the green check `.bounce(on:)` once on macOS 14+ (Compat); nothing on 13 | ≤ 0.5 s |

Under Reduce Motion every entrance is `Motion.standard(true)`: a 150 ms fade, no movement, no tilt, no flip.

### 3.5 Hover, press and selection

- `DuskButtonStyle` and `KeyCapStyle` sink 1–2pt on press with `Motion.pop`; shadows are constant per state and never
  animated (§1.4).
- Ticking a row toggles its checkbox with the system's animation; the residue bar's segment lit edge swaps to violet
  with `Motion.pop` (a colour swap, not movement; shown under Reduce Motion too). The bar's segment widths do not
  change on a tick (they are bytes by class, not by selection).
- `HoverTilt` is used on exactly three views in the whole app (the welcome drop zone, the first-run icon, the card
  preview on the result and Trace Report sheets), never more than two on screen at once: never on list rows, group
  cards, the residue bar or bars.
- Hover state lives in the modifier's `@State`, never in `AppModel`.

### 3.6 What doesn't move, and why

- The optional menu bar glyph never animates; it has no badge (DESIGN §6.4).
- The quiet state is still: a green check and a sentence. Calm is the resolution, not a celebration.
- The confirm sheet is still. People read it before moving files, even ones they can put back.
- The group cards' layers (`.layered()`) are static rims: depth is drawn, not animated.
- The readiness panel never animates: it is a list of facts.
- Nothing in `TraceCardView` moves (`ImageRenderer` draws it); decoration sits outside it on the sheets.
- No loop anywhere except the system `ProgressView` while a scan or a move runs.
- **Not doing:** a progress bar by percentage (scans report by place, BUILD_PLAN §7.2); a `matchedGeometryEffect`
  from a row to the Trash (there is no visible Trash in the window); keyframe or phase animators; glass on content;
  symbol effects beyond the one bounce on macOS 14+; a shake on a failed row (§1.1 rule 3).

## 4. Budgets, acceptance and how to verify without a Mac

### 4.1 Budgets

| Website item | Hard cap | Measure |
|---|---|---|
| `site/static/styles.css` | 40 KB | `wc -c`; `BUDGET` in `build_site.py` |
| `site/static/motion.js` | 6 KB (shared 2.7 KB + the sweep ≈ 0.6 KB) | `wc -c`; `diff` against Overstay's shows only the two attribute reads |
| Webfonts, CDNs, third-party requests, trackers | 0 | the Network panel on a cold load |
| Home HTML (built) | 36 KB | `wc -c site/_dist/index.html` |
| Home first load, uncompressed (HTML + CSS + JS + icon + favicon) | 110 KB | sum of the above |
| Hero sequence | ≤ 2.6 s, once; ≤ 4 planes | §2.1 table |
| The peel / the flip | ≤ 0.9 s / ≤ 0.6 s per press; reversible | §2.1 tables |
| CLS / LCP | 0 / the h1 | the siblings' snippets |

| App item | Budget |
|---|---|
| CPU after any entrance settles (welcome, first run, preview, result, card) | 0% in Activity Monitor within 2 s |
| Loops | only the system `ProgressView` while a scan or a move runs |
| The fade | ≤ 1 s for the whole list after the last outcome; per-row 0.6 s on a 45 ms stagger, cap 8 |
| Entrance lengths | welcome and first-run ≤ 1 s; group card flips ≤ 0.6 s; card deal ≤ 0.5 s |
| `HoverTilt` views on screen | ≤ 2 |
| macOS 13 | every API outside `Compat.swift` is macOS 13 |
| New files | `App/DesignSystem/{Tokens,Compat,Outline,ResidueBar,Layered,MenuBarIcon}.swift`; no assets beyond the icon set, no dependencies |

### 4.2 Acceptance checklist

**Website, all pages**

- [ ] `python tools/build_site.py --check` passes: links (including `/motion.js`), one `<h1>`, alt text, contrast with
      exactly two `:root` blocks, no `data-theme`/`localStorage`, no inline style or script, the exact CSP, budgets,
      no banned phrase in the built pages.
- [ ] With Reduce Motion: the found state is simply there (horizon lit, outline, five layers, tray, card); nothing
      lifts, steps or tilts; pressing the move button swaps to the swept state instantly and Reset demo swaps back;
      the card button swaps the faces instantly.
- [ ] With JavaScript off: the page is complete and still in the found state and both buttons stay hidden.
- [ ] Light and dark are right: a cool paper desk by day, a cool near-black desk before sunrise; the horizon is teal
      in both; the card keeps its fixed night colours.
- [ ] At 360×740: no horizontal scroll; the tray and card are hidden; the stack is static under the copy; the peel
      still moves the layers and fades the outline.
- [ ] Firefox shows the reveal fallback and the slabs' `step` keyframe ending at per-element `--dx/--dy/--dz`. Print
      of the "What it reads" page shows dark text on white, no shadows, no motion artifacts.
- [ ] Performance: no long task from `motion.js`, no layout or paint while tilting, peeling or flipping (only
      compositor properties plus the one `background-color` transition on the tray's edge).

**Website, hero**

- [ ] The horizon lights, the desk pools, the icon lifts away and leaves its outline, five layers step out one by one,
      the tray settles, the card deals in. The page is still after about 2.6 s.
- [ ] Move 4 items to Trash peels four layers into the tray in order, the Hands-off layer stays, the tray reads 4,
      the outline fades to a trace, the live region says "Sample: moved 4 items to the Trash, 1 listed only", and
      the button reads "Reset demo" with `aria-pressed="true"`. Keyboard (Tab, Space, Enter) and tap both work; hover
      never peels.
- [ ] Turn the card over shows the footer sentence and "Not covered"; `aria-pressed` follows.
- [ ] The headline, lede, both page buttons and the trust line never move.

**App** (on a Mac, or in CI once it compiles)

- [ ] Welcome: the drop zone's tile rises once; the zone tilts up to 6° with glare; the key-caps sink on press.
- [ ] First run: the icon rises once and tilts up to 8° with glare; Continue sinks on press.
- [ ] Preview: group cards flip in once per scan; ticking a row swaps the bar's lit edge; during a move each row
      leaves as its outcome is reported, content first, then the outline, the last within 1 s; after the rescan the
      remaining rows and segments re-lay out with a spring.
- [ ] Result and Trace Report: the card is dealt once, then tilts up to 4° with glare; Save PNG is byte-for-byte
      unaffected by the decoration (compare a PNG saved before and after any change outside `TraceCardView`).
- [ ] macOS 13: everything works without the Compat touches. Reduce Motion: fades only; no tilt, no flip, no sink,
      no stagger, no outline. VoiceOver: each row reads "Name, tier, size, reason"; the residue bar reads its legend;
      the countdown is not announced on every change (`.accessibilityValue` updates only at the end).

### 4.3 How to verify without a Mac

```sh
python tools/build_site.py --check
wc -c site/static/styles.css site/static/motion.js
diff site/static/motion.js ../overstay/site/static/motion.js   # only the sweep job's attribute reads may differ
python tools/build_site.py && python -m http.server 8768 --directory site/_dist   # open http://localhost:8768/aftertaste/ after copying under that prefix
```

- **Chromium:** DevTools Rendering › emulate `prefers-reduced-motion` and `prefers-color-scheme`; the 360px device
  toolbar; `document.getAnimations()` to step the hero; a `PerformanceObserver` for `layout-shift` and
  `largest-contentful-paint`; the Performance panel while pressing the move button (no Layout or Paint entries beyond
  the tray edge's colour).
- **Firefox on Windows** covers the reveal fallback, `var()` in keyframes and `:has()`. **Safari** needs the owner's Mac.
- **App, by review until CI compiles it:**

```sh
grep -rn "#available" App/ | grep -v DesignSystem/Compat.swift                                                     # nothing
grep -rn "symbolEffect\|phaseAnimator\|keyframeAnimator\|visualEffect\|\.smooth(\|spring(duration" App/ | grep -v Compat.swift   # nothing
grep -rn "repeatForever\|TimelineView" App/                                                                       # nothing (the only loop is the system ProgressView)
grep -n "rotation3DEffect\|HoverTilt\|FlipFaces\|shadow\|material" App/Report/TraceCardView.swift                 # nothing: the PNG stays clean
grep -rn "\.animation(" App/ | grep -v "value:"                                                                   # nothing
grep -rn "HoverTilt(" App/ | wc -l                                                                                # 3
```

- Then the macOS CI build is the first compile. Until it is green, call the app code "written, not compiled".

### 4.4 Proposals for other owners (not made here)

- **site (`site/**`):** §2.2–§2.5; `motion.js` = the shared file plus §2.4's job; the `#i-ok` and `#i-mark` sprite
  symbols; the `data-sweep-said` / `data-sweep-reset` strings.
- **infra (`tools/build_site.py`):** `BUDGET["motion.js"] = 6_000`; in CI run the §4.3 app greps as failures.
- **app-shell (`WelcomeView`, `FirstRunView`):** §3.4's entrances and the two tilts.
- **app-content (`PreviewView`, `GroupSection`, `ItemRow`, `ResultView`):** §3.2's `departed` and the `.outline`
  transition; the group card flips; §3.3's card deal on the result sheet.
- **app-report (`TraceCardView`):** nothing moves inside; the deal and tilt wrap it from outside.
- **architect (BUILD_PLAN §7, frozen):** add "Motion: docs/MOTION.md; design: docs/DESIGN.md" to §7, and note that
  `.running(plan, finished:)` plus the outcomes reported so far is enough for the fade (the view needs to know which
  of the first `finished` items were moved; if `AppModel` does not expose partial outcomes, the fade uses `finished`
  alone and every reported row leaves, with the result sheet correcting the picture).

**VERIFY (on a Mac or in Safari):** the per-function transform interpolation on the peel in all three engines;
`var()` in `@keyframes` and `:has()` in Firefox; `backface-visibility` inside a `preserve-3d` card in Safari; the
`Outline` transition's removal timing with per-row delays on `.transition(_:).animation(_:)`; `.contentTransition(.numericText())`
with fast changes; `FlipFaces` and `HoverTilt` signs; `Motion.spring` delays on `.animation(_:value:)` with per-row
offsets.
