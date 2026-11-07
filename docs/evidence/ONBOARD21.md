# ONBOARD21 — optional hint idle-clock integrity

## Proven UX problem

`OnboardingCard.advance_idle()` accrued elapsed time even while optional
onboarding hints were explicitly disabled. Re-enabling hints then immediately
revealed a later-tier automated hint, even when the player had only just opted
in. The card also previously had no distinction between reapplying the same
preference (on viewport/scale refresh) and a genuine toggle.

## Implementation

- Pause the optional hint timer when hints are disabled.
- Reset elapsed hint time and visible hint text only when the setting actually
  changes; repeated unchanged settings refreshes preserve requested help.
- When re-enabled, use the existing 20/45/90-second progression from zero.
- Preserve the essential tutorial instruction, ordered accepted-event
  progression, manually requested hints and bounded localized strings.
- Add five Godot regression tests in
  `tests/unit/test_ONBOARD21_hint_opt_out_clock.gd`, with a tracked Godot
  `.gd.uid` sidecar for reproducible Windows imports.

## Verification and release boundaries

Run exact-head Linux and Windows full `bash tools/run_tests.sh`, Windows
release export/headless smoke, CodeQL, and applicable resource probes before
merge; verify post-merge `main` CI. This work has no changes to host
authority, mission scoring, Steam, saves, content contract hashes, network
commands or opt-in telemetry schema. Human UX01 physical-controller and
first-repair discoverability remain unverified, as do V09/F02/F06.

## Resume notes

Review final CI and only merge on green. Avoid treating automated prompt
timing as a substitute for the human tutorial acceptance study.
