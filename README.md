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
