# Mwifi website design

## 1. Theme

A light, native macOS product page for people deciding whether to download Mwifi. Actual SwiftUI view captures carry the visual story. The page feels quiet, useful, and precise.

## 2. Palette

Use OKLCH tokens in one plain CSS stylesheet: canvas `oklch(97.8% 0.004 260)`, ink `oklch(24% 0.026 260)`, muted `oklch(49% 0.024 260)`, accent `oklch(51% 0.20 260)`, pale blue `oklch(94.5% 0.021 260)`. Blue denotes downloads and links; green appears only in real app data or status indicators.

## 3. Typography

Use the native Apple system sans stack and PingFang SC for Chinese, with system fallbacks. This matches the app and avoids third-party font requests. Hero: 64px/1.16 at weight 650. Section title: 40px/1.25 at 650. Body: 17px/1.8. Captions: 13px/1.6. Display tracking: -0.025em. Numeric labels use tabular figures.

## 4. Components

Primary links are blue, 12px-radius buttons with a 44px minimum height. Secondary links are text, with visible underline on hover. Screenshots are buttons opening a native dialog, with a labelled close button, Escape support, and focus restoration. FAQ uses native details/summary. Focus indicators remain visible.

## 5. Layout

Maximum content width: 1160px. A left-aligned hero introduces the app beside its menu capture. A wide traffic screenshot follows a short explanatory section. Compact feature rows lead into installation and FAQ. The footer is a single row, not a link directory.

## 6. Depth

Only screenshot frames use layered shadows, expressing a floating macOS window. Other content stays on the page with whitespace and hairline dividers. Radius tokens: 6px, 12px, 20px, 28px. Do not use backdrop blur.

## 7. Guardrails

- Never present synthetic screenshot data as measured performance.
- Keep personal SSIDs, live traffic, local paths, and credentials out of assets.
- State the U30 Air compatibility boundary and the unsigned/notarization limitation accurately.
- Do not invent an open-source license, ratings, testimonials, or download counts.
- No analytics, external fonts, cookie storage, or automatic GitHub API calls.
- Keep the download link functional without JavaScript.

## 8. Responsive behavior

Below 900px, stack the hero with the screenshot beneath the copy. At 600px and below, reduce display typography and margins; keep all controls at least 44px tall. Traffic screenshots stay full-width and open at readable size in the viewer. Honor reduced motion, keyboard access, and safe-area insets.

## 9. Maintenance guide

Use the existing blue accent for links only. For a new section, use a 40px, weight-650 title with -0.025em tracking and a 17px/1.8 paragraph in muted ink. Add screenshot frames with a 20px radius and the existing screenshot shadow. Prefer plain rows to repeated cards. Update version-specific download references when publishing an app release; website-only changes do not rebuild the app.
