# Symphony Dashboard Design System

This document records the first design-system layer for the Symphony dashboard and
session observer UI. The reference import lives in `references/session-viewer/`.

## Goals

- Keep the existing operations dashboard readable while the session viewer is
  split into a richer interface.
- Use shared tokens for surfaces, borders, text, cache state, thread state,
  warnings, and errors.
- Prefer reusable `ds-*` classes for new dashboard UI so Codex, Gemini, Claude
  Code, and OpenCode session adapters can present the same concepts.

## Token Groups

- Surfaces: `--surface-canvas`, `--surface-base`, `--surface-panel`,
  `--surface-panel-muted`, `--surface-raised`.
- Borders: `--border-subtle`, `--border-strong`.
- Text: `--text-primary`, `--text-secondary`, `--text-tertiary`.
- Signals: `--signal-cache`, `--signal-thread`, `--signal-warning`,
  `--signal-danger`, plus matching soft/ink variants where needed.
- Shape: `--radius-xs`, `--radius-sm`, `--radius-md`, `--radius-lg`.

## Components

- `ds-shell`: root dashboard surface wrapper.
- `ds-panel`: shared panel/card treatment.
- `ds-panel-hero`: larger first-viewport panel treatment.
- `ds-tabs` and `ds-tab`: navigation between runtime and session-observer
  surfaces.
- `ds-pill`: compact state badge base.
- `ds-pill-cache`, `ds-pill-thread`, `ds-pill-warning`, `ds-pill-danger`:
  semantic badge variants.
- `ds-code`: monospace numeric/code text.
- `ds-meta-grid` and `ds-meta-item`: compact key/value metadata layout.
- `ds-session-card`: repeated session summary item surface.

## Surfaces

- `/`: operations dashboard for the original Symphony runtime, active workers,
  retry pressure, rate limits, and token totals.
- `/sessions`: session observer for cloned external-session summaries, cache
  hit visibility, provider distribution, interpreted observer output, and
  collapsed raw session details.

## Next Steps

- Add provider/platform icons and color semantics for Codex, Gemini, Claude
  Code, and OpenCode after adapter payloads expose platform consistently.
- Introduce collapsed raw envelopes with interpreted summary-first rendering.
