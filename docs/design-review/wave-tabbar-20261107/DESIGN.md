---
name: Huevia Wave Tabbar review prototype
description: Local browser proposal pending user review; no native or global design authority.
colors:
  paper: "#f8f7f4"
  ink: "#242320"
  muted: "#706b63"
  capsule: "#ffffffed"
  preset: "#70d5f1"
  sync: "#83d38f"
  album: "#f58e88"
  settings: "#8e7bec"
  icon-detail: "#ffe878"
  preset-tint: "#e5f3f8"
  sync-tint: "#e8f3e9"
  album-tint: "#f9e9e5"
  settings-tint: "#ede8f7"
  preset-ink: "#276478"
  sync-ink: "#35664c"
  album-ink: "#8c4b43"
  settings-ink: "#605084"
typography:
  label:
    fontFamily: "'Segoe UI Variable', 'Segoe UI', 'Microsoft YaHei UI', 'PingFang SC', sans-serif"
    fontSize: "11px"
    fontWeight: 450
    lineHeight: "13px"
  label-selected:
    fontFamily: "'Segoe UI Variable', 'Segoe UI', 'Microsoft YaHei UI', 'PingFang SC', sans-serif"
    fontSize: "11px"
    fontWeight: 650
    lineHeight: "13px"
rounded:
  capsule: "32px"
  selection: "28px"
spacing:
  inset: "4px"
  icon-label-gap: "3px"
components:
  navigation:
    backgroundColor: "{colors.capsule}"
    rounded: "{rounded.capsule}"
    padding: "{spacing.inset}"
    height: "64px"
  navigation-item:
    textColor: "{colors.muted}"
    typography: "{typography.label}"
    rounded: "{rounded.selection}"
    padding: "4px 0"
    height: "56px"
---

# Design System: Huevia Wave Tabbar review prototype

## Overview

**Creative North Star: "A compact white floating capsule with pastel functional icons."**

This records the built browser proposal in this folder, derived from `wave.css` and `wave.js`. The user-pinned Wave Tabbar and four supplied frames inform the component; existing warm photo homes supply illustrative context. It is ready for user review, with approval still pending. It grants no authority to change the root design system, Android, processing interfaces or release artifacts.

**Key Characteristics:**

- Four visible functional names in the established order: 预设 / 同步 / 相册 / 设置.
- All icons coloured at rest; one whole icon-and-name pale selection.
- A brief wave acknowledgment followed by a still resting state.

## Colors

### Primary

Preset sky, sync green, album coral and settings lavender are parallel entry identities. Yellow supplies small icon details. No entry colour acts as a global brand primary.

Each identity has its own pale selected ground and deeper selected name ink, recorded in the frontmatter. The small name carries the readable selection signal alongside the background; the pastel silhouette is not the sole state cue.

### Neutral

Warm paper supports the photo context. The capsule is translucent white; muted ink identifies inactive names and deep neutral ink supports the existing content.

**The Coloured Rest Rule.** Keep all four icon identities coloured after the animation; selection is indicated by the whole pale capsule and deeper, heavier name.

## Typography

The local UI uses the recorded Windows-first UI font stack with Chinese fallbacks. Navigation names use the label role, with the selected weight defined separately. This does not establish a production display face or a project-wide type ramp.

At the narrow breakpoint (340px), names become smaller (10px); line height remains unchanged. Existing page titles and board annotations belong to their illustrative/review roles, not to this component's reusable type system.

## Layout

The navigation has four equal columns. Its outer height, padding and item height are recorded above. The selected ground is exactly one column wide after removing both outer insets; icon and name share its bounds. Icons occupy a square (28px), reducing to 27px at the narrow breakpoint. The icon/name gap uses the recorded spacing token.

In the single-screen browser view, the bar sits above the home indicator with side offsets (15px), bottom offset (19px) and maximum width (420px). These are this browser composition's placements, not Android safe-area specifications. The board presents the interactive phone, four selected states and three static motion phases; it stacks below its narrow board breakpoint (720px).

## Elevation & Depth

The capsule uses a restrained diffuse shadow (`0 10px 28px -16px #554b404d`) and backdrop blur (20px). Its translucent white surface remains visually distinct over warm paper and photos. The selected ground is flat tint, without an extra shadow. The review phone frame's shadow is presentation furniture rather than navigation elevation.

## Shapes

The outer capsule and selected ground use concentric radii from the frontmatter. The selected shape includes both icon and label. Function icons are authored solid SVG geometry, with an SVG clipping wave used only during selection.

**The Even Inset Rule.** Preserve the same outer inset on all sides; the selected ground is not a separate icon badge.

## Components

### Wave navigation

Compact, colourful and quiet at rest. Each entry is a real button with an accessible name; the active entry has `aria-current="page"`. Focus uses the shared visible outline (2px, offset 4px). Left/Right, Home and End select and focus entries. The browser content title and selected state update together.

Selection translates the pale ground (220ms, `cubic-bezier(.16,1,.3,1)`), changes its tint (180ms), and plays one icon-only grey-to-colour wave fill (440ms, `cubic-bezier(.16,.65,.28,1)`). A new selection cancels the prior fill and replay sequence; selecting an entry again can replay its fill. There is no idle animation.

Reduced-motion CSS removes the travelling fill and press scale; JavaScript also skips starting the wave when the OS preference is active. Colour/opacity transitions remain brief (100ms). This path was inspected in source, not exercised with an emulated OS preference.

### Review replay control

A white rounded button replays the four root states at a fixed interval (760ms). It exists only on the review board. Clicking a navigation entry interrupts replay. Existing source switches and content actions remain illustrative; they do not establish camera, account or photo workflows.

## Do's and Don'ts

### Do:

- **Do** keep all four names visible and include the full icon/name pair in the selected ground.
- **Do** preserve equal insets, concentric radii and the coloured resting state.
- **Do** keep selection interruptible, keyboard accessible and responsive to reduced motion.

### Don't:

- **Don't** add an idle wave loop or turn the selected ground into an icon-only badge.
- **Don't** treat this review prototype or its browser evidence as user approval, native validation or a global design change.
- **Don't** promote illustrative photo layouts, account text, transfer status, review furniture or the local system font stack into production design rules without a separate decision.
