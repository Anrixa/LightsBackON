# Lights Back On (working title)

A pre-release, first-person cooperative repair game about restoring power to a storm-damaged neighborhood. The design targets solo play and friends-only co-op for up to four players on Windows/Steam.

**Project status:** active development. The presence of automated tests and build jobs does not mean that multiplayer, Steam integration, or real-hardware gameplay has passed final validation.

## Engine and targets

- **Engine:** Godot 4.7.2, standard (not .NET), with typed GDScript.
- **Renderer baseline:** Compatibility.
- **Primary target:** Windows x64. Linux runners provide automated validation, not a supported Linux release commitment.
- **Main scene:** `scenes/boot/boot.tscn`.

## Open and run

1. Open `project.godot` in Godot 4.7.2.
2. Let the editor import the project assets.
3. Run the configured main scene.

For automated tests on Linux, the repository provides:

```bash
export GODOT_BIN="$(bash tools/setup_godot_linux.sh)"
bash tools/run_tests.sh
```

The Windows CI uses `tools/setup_godot_windows.sh` and `tools/run_tests.sh` through Git Bash. See `.github/workflows/ci.yml` for the exact environment and export pipeline.

## Offline-first playable C01 (Steam not required)

The Windows build now has a **Start Solo Shift** entry point. The boot scene keeps its log and internal save-soak mode, then opens a windowed main menu. Select **Start Solo Shift** to enter the authored Alder Street graybox as a colliding first-person worker, with the field HUD, network tablet, onboarding hints, and local pause/accessibility menu. All power and repair state transitions still pass through the existing authoritative C01 host command handlers. Steam mode remains disabled and unqualified.

To run from a checked-out Godot 4.7.2 project, open `project.godot` and press **F6** in the boot scene or **F5** to run the main project. In a Windows export, launch `LightsBackOn.exe` normally (without `--headless`). The export templates and exact verification commands are in `docs/PC-RUNBOOK.md`.

Controls in this development build: WASD / left stick to move, mouse / right stick to look, E / south face button or primary tool to interact, mouse wheel, keys 1–5, or D-pad left/right to select any of the five tools, Tab / left shoulder for the network tablet, and Esc / menu button to pause. G / X drops the carried generator at a safe authored anchor. The reticle and host both reject world interactions blocked by collision before accepting a command. Physical repair actions depend on meter evidence, repair locks, isolation, the selected tool, and host validation; generator placement and extraction use authored world pads/zones. UI presentation settings are currently session-local, and camera/VFX preferences await actual live effect producers.

**Local progress and accessibility saves:** The solo menu now exposes **Continue Shift** when a valid checkpoint exists and **New Solo Shift** with a confirmation before replacing the current checkpoint. Mission progress saves immediately after durable actions, on the host interval, on pause, and on exit. Power and repair state use the existing G06 checkpoint format, while last position, view orientation and selected tool are stored as bounded integer presentation fields. The save identity is a random, local-only pseudonym kept in the Godot user-data directory. The game refuses to overwrite corrupt, newer-schema or different-content saves; incomplete writes can recover from verified temp/backup copies, with errors shown to the player. Accessibility preferences persist separately across shifts. **Do not manually delete the Godot user-data directory** if you want to keep this progress. This is not Steam Cloud or a verified power-loss guarantee.

**Controller and accessibility overlays:** HUD and tablet binding hints automatically follow the last intentional gamepad or keyboard/mouse input. Opening the network tablet transfers focus inside; switching UI scale or input device retains the focused map node or action. Pause focuses Resume, and Accessibility opens on the first scale button; one Back closes nested settings and the next resumes play. On smaller viewports, the pause/actions panel scrolls instead of expanding past the screen. Scene tests use a separate headless profile directory, so CI cannot overwrite normal windowed solo progress.

**Acceptance boundary:** CI's headless scene instantiation and known-solution trace are not proof of controller feel, visual performance, real-world reachability, or co-op. Steam F02/F06, G08, V09 and human UX gates remain outstanding. No account or Steamworks access is needed for this offline development route.

## Source layout

| Path | Purpose |
| --- | --- |
| `scenes/`, `scripts/` | Godot scenes and gameplay systems |
| `content/`, `assets/`, `art_source/` | Game content and visual assets |
| `reference/` | Reference implementations and validation |
| `tests/` | Automated gameplay and contract checks |
| `tools/` | Godot setup, tests, export support and build verification |
| `docs/backlog.json`, `docs/adr/` | Work status and decisions |
| `docs/HANDOFF.md` | Development and local verification handoff |

## Verification boundaries

The CI workflow runs Linux and Windows headless checks and creates a Windows export. It **cannot** replace testing real graphics hardware, a Steam-enabled client, or two independent machines/accounts for online co-op. Do not infer deployment or publication from a successful CI badge.

## Collaboration and privacy

Read `CLAUDE.md` and the relevant architecture and decision documents before changing game contracts. Never commit Steam credentials, signing keys, private notes or machine-specific configuration. The repository's `.gitignore` lists local-only material.

## License

No project-wide open-source license is declared here. Do not assume the game source, art, or other bundled materials are available for reuse merely because this repository is publicly readable.
