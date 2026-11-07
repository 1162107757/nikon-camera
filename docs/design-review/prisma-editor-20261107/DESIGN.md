---
name: Huevia Prisma editor prototype
description: Scoped record of the completed photo-first web concept, not the native app design system.
colors:
  ink: "#202b2b"
  muted: "#5c6b6c"
  yellow: "#ffe335"
  photo-white: "#fff"
  tool-dark: "#1014129c"
typography:
  title:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", "Microsoft YaHei", sans-serif'
    fontSize: "13px"
    fontWeight: 500
    letterSpacing: ".02em"
  label:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", "Microsoft YaHei", sans-serif'
    fontSize: "10px"
    fontWeight: 400
  control:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", "Microsoft YaHei", sans-serif'
    fontSize: "11px"
    fontWeight: 400
rounded:
  thumbnail: "7px"
  choice: "10px"
  pill: "24px"
  circle: "50%"
spacing:
  control-gap: "7px"
  filter-gap: "14px"
  row-gap: "12px"
  workspace-inset: "20px"
components:
  button-export:
    backgroundColor: "{colors.yellow}"
    textColor: "#191e17"
    rounded: "{rounded.pill}"
    padding: "10px 17px"
  tool-circle:
    backgroundColor: "{colors.tool-dark}"
    textColor: "{colors.photo-white}"
    rounded: "{rounded.circle}"
    width: "39px"
    height: "39px"
  choice:
    backgroundColor: "#111b18a1"
    textColor: "{colors.photo-white}"
    rounded: "{rounded.choice}"
    padding: "9px 11px"
---

# Design System: Huevia Prisma editor prototype

## Overview

**Creative North Star: "The photograph owns the editor"**

The photograph supplies both the focal image and the blurred surrounding atmosphere. Compact controls sit beneath it; dark round tools, small image thumbnails and a saturated yellow export action carry the pinned Prisma vocabulary. This records only the built concept in this directory. It does not establish a global Huevia identity or a production Android implementation.

**Key Characteristics:**
- Photo-derived color and depth.
- Circular dark tools with inline SVG line icons.
- Yellow export and selected-state signals.
- Direct original/effect comparison and new-copy JPEG export.

Source authority: [Prisma Photo Editor by Daria Bugrowskaia / Prisma Labs](https://dribbble.com/shots/15854036-Prisma-Photo-Editor), as pinned by the user. `assets/provenance.json` records the existing project sample used for `portrait.jpg`; it is an illustrative 4:5 crop, not camera-output evidence. The saved reference image is for inspection and is not displayed in the prototype.

Verification boundary: the local HTTP version was exercised for looks, strength, undo, exposure, comparison seam, square crop, rotation and white-frame JPEG export with no browser console warnings or errors. Final captures are `.impeccable/review/desktop.png` (1264×1052), `mobile.png` (390×844) and `narrow.png` (320×640). The review's ship verdict covers its named label-collision fix only. The offline `prototype.html` passed embedded-resource and extracted-script syntax checks; direct `file://` browser access was blocked by browser policy and was not bypassed or browser-verified. The detector used a regex fallback; its clean result is not computed-contrast certification. CSS looks and portrait controls demonstrate color/layout rather than real presets or portrait algorithms.

## Colors

### Primary

Yellow marks export, active tools, selected thumbnails and range progress. It remains a control signal against the photograph-derived background.

### Neutral

Photo white carries editor labels and icons. Translucent tool dark isolates controls from the changing photograph. Ink and muted support the desktop presentation board outside the editor.

**The Photo Atmosphere Rule.** Derive the editor backdrop from the active photograph; retain the dark overlay that separates controls from its colors.

## Typography

The built editor uses the platform sans stack for an operating interface. Small labels, slightly larger parameter text and a centered filename form its hierarchy; there is no editorial display face. Numeric slider values use tabular figures. The desktop board's heading and wordmark are presentation furniture, not a reusable native branding rule.

## Layout

The desktop board has three equal editor columns inside a maximum width of 1240px, with 28px side padding and 32px gaps. Each editor divides into status, header, flexible photograph, history, tools and bottom workspace. The photo starts at 4:5 and changes with the crop state.

At widths from 701px through 1100px, the board wraps 340px columns. At 700px and below, presentation furniture disappears and one editor fills the viewport using `100svh` with safe-area insets and a 580px minimum height. A short-phone rule at height 690px reduces row heights and thumbnail height. Horizontal filter scrolling preserves compact choices rather than wrapping them into the photograph.

## Elevation & Depth

Depth comes primarily from the photo backdrop, blurred by 38px and darkened with a vertical overlay. The desktop device frame has a diffuse shadow; mobile removes that frame shadow. Small shadows lift the comparison handle and range thumb. State transitions last 180ms; transforms use `cubic-bezier(.16,1,.3,1)`. Reduced-motion preference removes transitions.

## Shapes

Tools and comparison toggles are circular. Export uses a pill; thumbnail and choice corners stay compact. The desktop editor frame is rounded by 34px, while the mobile editor is edge-to-edge. The photograph remains a clean rectangular crop.

## Components

- **Export:** yellow pill, at least 68×42px, bold 13px label; lighter yellow hover and disabled in-progress state. Export creates a new demonstration JPEG.
- **Tools:** five labeled SVG actions; 39px dark discs inside targets at least 48px wide. Selected tools use yellow labels/icons and a darker disc. Short phones reduce discs to 34px.
- **Filter rail:** 66px cards, 70px on phones, with an image and short label. Cards have 14px exterior gaps following the user's spacing feedback. Selection adds a yellow outline and an SVG check; scrolling stays horizontal.
- **Category navigation:** compact text buttons; selected text gains weight and a short yellow underline. Its hit region extends beyond its visible text.
- **Ranges and choices:** thin yellow progress, white circular thumbs and tabular values. Crop/frame choices use rounded dark buttons with yellow selected text and an inset outline.
- **Comparison:** two photo layers, a white movable seam and a keyboard-operable transparent range. Labels reserve space before the top-right 48px compare toggle; the corrected label row uses a 64px right inset.
- **History:** undo and redo use circular 300-degree arcs with connected rounded arrowheads; redo is a horizontal mirror. The SVG symbols and offline HTML were synchronized after the user's circularity feedback. Current native implementation and validation are recorded separately in [153's implementation record](../../selection-soft153.md); it does not relabel the preceding browser captures or update this approved prototype's selection materials.
- **Focus and press:** visible focus uses a 3px blue outline with 4px offset; enabled buttons scale to .96 when pressed. The comparison range has its own yellow focus treatment.

## Do's and Don'ts

### Do:
- **Do** preserve the photo-first hierarchy and its image-derived backdrop.
- **Do** pair selected color with a check, underline or visible control state.
- **Do** keep original/effect labels clear of the compare control and retain the movable seam.
- **Do** label demonstration behavior honestly and preserve new-copy export.

### Don't:
- **Don't** promote this bounded concept into the native app's global design system.
- **Don't** treat CSS looks, illustrative imagery or portrait controls as production processing claims.
- **Don't** present the scoped review or detector fallback as comprehensive accessibility or native acceptance certification.

Not canonized: desktop presentation geometry, isolated board decoration and the review's corrective 64px inset are recorded as local implementation facts, not general design tokens. No craft-floor refusal is promoted into a reusable rule.
