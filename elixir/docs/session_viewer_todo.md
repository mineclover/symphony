# Session Viewer Work Status

Last updated: 2026-05-06 KST

## Current State

- Main feature commit:
  `d8c429a feat(observer): add session viewer and external session summaries`
- Server route:
  - Runtime dashboard: `/`
  - Session observer: `/sessions`
- Current uncommitted change:
  - `elixir/priv/static/dashboard.css`
  - Purpose: reduce oversized typography and whitespace in the dashboard and
    session viewer UI.

## Done

- [x] Add external session adapter behavior for non-Linear session sources.
- [x] Add Codex CLI history adapter and session JSONL parsing.
- [x] Detect session updates from Codex history by session id, status, mtime,
      latest user query, and cache metadata.
- [x] Fork/clone Codex observer sessions and ask summary prompts without
      mutating the source session.
- [x] Persist session inspection records to JSONL.
- [x] Expose session inspections through the observability presenter and API.
- [x] Add external ingest API for sessions pushed by external tools.
- [x] Track source cache and observer cache separately.
- [x] Split the runtime dashboard and session observer into separate surfaces.
- [x] Add `/sessions` LiveView for session summaries.
- [x] Import reference design into `references/session-viewer/`.
- [x] Add dashboard design tokens and reusable `ds-*` primitives.
- [x] Add design-system notes in `elixir/docs/design_system.md`.
- [x] Reduce UI typography and spacing density after first visual pass.

## Validate Before Next Commit

- [x] `mix test test/symphony_elixir/extensions_test.exs`
- [x] `git diff --check`
- [ ] `mix format --check-formatted`
- [ ] `mix specs.check`
- [ ] Decide whether to commit the CSS density adjustment separately.

## Next UI Work

- [ ] Add a clearer list/detail layout for `/sessions` so operators can scan
      sessions on the left and read the selected summary on the right.
- [ ] Collapse failed/old/pending records by default, with active recent
      summaries expanded first.
- [ ] Add provider badges for Codex, Gemini, Claude Code, and OpenCode.
- [ ] Add cache visualization that distinguishes:
      source cache hit, observer cache hit, no cache, and failed observer turn.
- [ ] Add filtering controls for provider, status, cache hit, and active/recent
      sessions.
- [ ] Add sorting controls for updated time, cache ratio, and failure state.
- [ ] Make raw session details less visually dominant; keep interpreted summary
      and latest user query first.
- [ ] Consider paginating or virtualizing old session records once history grows.

## Next Backend Work

- [ ] Standardize adapter payloads across Codex, Gemini, Claude Code, and
      OpenCode.
- [ ] Add a provider-neutral observer prompt contract.
- [ ] Add a provider-neutral clone/fork strategy field and capability check.
- [ ] Record observer failure classes in structured fields instead of only
      textual error summaries.
- [ ] Add retry/backoff rules for observer summary failures.
- [ ] Avoid repeatedly summarizing stale historical sessions unless explicitly
      requested.
- [ ] Add a retention policy for `.symphony/session_inspections.jsonl`.
- [ ] Add API endpoints scoped to session summaries, not only global state.

## Known Issues

- Some observer summaries fail when the source model is `gpt-5.5` but the
  local Codex app-server is older than the model requires.
- Some historical Codex sessions are still shown as pending or failed; the UI
  should separate historical backlog from active/recent work.
- Full test runs have shown intermittent SSH fake trace timing failures. The
  failed SSH test passed when rerun by itself during the last validation pass.
- `/sessions` currently renders all records as a single list, which is usable
  but still too heavy for large histories.

## Suggested Next Commit

Commit only the CSS density adjustment after running the remaining validation:

```bash
cd elixir
/opt/homebrew/bin/mise exec -- mix format --check-formatted
/opt/homebrew/bin/mise exec -- mix specs.check
/opt/homebrew/bin/mise exec -- mix test test/symphony_elixir/extensions_test.exs
cd ..
git diff --check
```

Suggested subject:

```text
style(observer): tighten session viewer density
```
