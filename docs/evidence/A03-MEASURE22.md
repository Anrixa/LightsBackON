# MEASURE22 — session-clock alignment and same-tick idle integrity

- **Status:** source implemented; CI verification pending. This is an additive A03 preparation phase, **not** the original roadmap A03 or V09 acceptance.
- **Date:** 2026-11-07 UTC.
- **Base main:** `eb73f4397925b2b1dd724340b7100845aeb929a0`.
- **Branch:** `task/MEASURE22-session-clock-idle-integrity`.
- **Environment:** GitHub Linux and Windows hosted runners; no on-device GPU, human playtest, or Steam qualification.

## Defects corrected

1. **Restored campaign tick contamination:** The live C01 scene previously used `max(local_session_tick, durable_event_tick)` for opt-in events. On resume the mission's old campaign tick could leap far ahead, causing all subsequent `observe_tick` and activity events to be refused as out of order. C01 measurements now use the scene's own monotonic 10 Hz observation clock only; durable mission event payloads cannot set observation timestamps.
2. **Host callback alignment:** Advance the scene observation tick before invoking the host's `tick_once()`; synchronous mission events now use the same host step index as objective observations.
3. **Completion timing:** When showing results, do not insert an old campaign completion tick into an unrelated local observation session.
4. **Same-tick idle integrity:** Real movement can end an idle span on exactly the tick it was detected. The GDScript exporter correctly omits the optional zero `value_ticks`; the MEASURE21 Python auditor previously rejected that truthful sequence. The auditor now permits **only** zero elapsed with an omitted duration field, never a fabricated numeric value. Positive durations remain strictly matched to the host tick difference.

All changes are diagnostic/presentation only. No grid, repair, rewards, save schema, transport or player control contracts changed.

## Verification plan

- `bash tools/run_tests.sh` — full Linux and Windows headless suites, including Godot `MEASURE22` live-scene regressions.
- `python -m unittest discover -s tests/python -p 'test_*.py' -v` — verifies Python audit invariants; three new `MEASURE22` regression methods.
- Windows release export and headless smoke check in `.github/workflows/ci.yml`.
- Exact PR-head GitHub CI and post-merge `main` CI to be recorded once completed.

Four new Godot regressions cover same-tick closure, exported JSON shape, resumed old campaign ticks, and malicious event timestamp exclusion. Three Python regressions cover valid zero, invalid fabricated zero and mismatched positive duration.

## Remaining gates

F02/F06 Steam two-network qualification, real Windows GPU/controller performance and usability, V09 ten solo/group playthroughs, A03 real observations, A05 recruitment and consent procedures. Do not claim full A03 acceptance or release readiness.

## Resume

After exact-head Linux/Windows CI and Windows export pass, merge PR and verify `main` CI. Next meaningful phase: make post-resume completed-checkpoint measurements explicit so a completed saved campaign cannot be counted as a new completed study session, and add a local consent/retention review gate without telemetry upload.
