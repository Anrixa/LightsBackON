# A03 preparatory batch — MEASURE01–MEASURE20: local validation observations

**Status:** source-implemented, CI verification required. A03 remains NOT_STARTED until V09 passes; the original 66-item backlog is unchanged.

## Scope

Twenty ordered engineering increments toward A03's local measurement events.
The C01 scene emits only opt-in local events. The recorder has no imports from
Steam/network, no account keys, no device addresses, no player coordinates,
no text chat and no gameplay-side effects.

| Batch | Phases | Implemented behavior |
| --- | --- | --- |
| 1 | MEASURE01–MEASURE05 | Default disabled; explicit policy; schema v1; enumerated, bounded, monotonic events; immutable inspection |
| 2 | MEASURE06–MEASURE10 | Objective-ordinal first visibility and transition-only completion; restored-baseline safety; host-tick idle start and measured idle end |
| 3 | MEASURE11–MEASURE15 | First successful repair; host trip and verification cues; real hint input; offline exit distinguished from a confirmed network disconnect; production C01 scene wiring |
| 4 | MEASURE16–MEASURE20 | No export without opt-in; fixed app-private directory; atomic local JSON; single finalization; complete end-to-end trace and staging cleanup |

## Opt-in and privacy

Godot user-argument flag: --lbo-local-measure (pass after the Godot -- separator).
Without this flag, normal play creates no local report. With it, C01 writes
only into user://local_measurements/ after completion or Return to Menu.
There is no telemetry upload.

Each JSON report contains schema_version=1, public contract C01, 10 Hz host
tick timestamps, numeric objective indices, bounded idle durations,
enumerated event kinds, and dropped-event count. File names are random,
never derived from account data.

Idle time uses simulation ticks, not wall clock, and paused sessions do
not accumulate idle. A solo quit never fabricates a Steam disconnection.
Real peer transport adapters must explicitly report confirmed disconnects.

## Gates and boundaries

Run 20 Godot tests in tests/integration/test_MEASURE20_local_events.gd.
Require full Linux/Windows CI, cross-check, Windows release export/headless
smoke, tracked UID checks and dedicated QA51 isolated resource probes
before merging. Record verified run IDs and exact head only after inspection.

Not verified: human Windows GPU/controller play, actual captured playtester
session, two-network Steam, live peer disconnect, and V09 acceptance.
V09 and A03 original roadmap tasks stay NOT_STARTED.

## Resume

Use a real opt-in Windows C01 playthrough to review event quality, then
establish a consent/retention procedure for playtester reports. Complete
physical V09 gates before promoting A03.
