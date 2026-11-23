# RB02: location format

Decision: `docs/adr/ADR-019-designed-locations-and-challenges.md`. Plan: `docs/design/RB-locations-and-challenges-plan.md`.
Evidence: `docs/evidence/RB02.md`.

A **location** is an authored place that a story contract or a challenge is played on. It is art and layout. A
**challenge** (RB03, `docs/design/RB03-challenge-format.md`) is data on top of it.

## Files

Each location is one folder: `content/locations/<location>/`.

| File | What it holds | Rules or presentation |
|---|---|---|
| `location.json` | The manifest: IDs, scene path, file names, physical grid, landmarks, spawns and opening shot, extraction zone, audit backdrop | Rules |
| `layout.json` | Kit layout on the 4 m grid: envelope, ground and pit, boundary, routes, buildings (kit faces per storey), kit placements, props, markers, zones, sightlines | Rules |
| `dressing.json` | Signs, plaques, cabinets, van, kerbs, lane marks, substation, poles, cable markers, skyline, capture views, DS11/DS12 presentation data | Presentation (`content/save_compat.json`) |
| `look.json` | Look profile: the shared look it builds on, environment overrides, building palette, street lamps | Presentation (`content/save_compat.json`) |

- **Rules files** are part of the rules revision (ADR-018). Changing one makes an existing offline checkpoint
  unresumable, which the player sees as "start a new shift"; nothing is erased.
- **Presentation files** can change without touching checkpoints.
- Rules code, such as the offline session, loads a location with `presentation = false`. It never reads the dressing or
  the look.

The shared look (`content/world/look_stormglass.json`) keeps what all locations share: sky, fog, tonemap, moon, rain,
surface materials, street lamp model, window colours and sign style. A location's `look.json` adds what makes the place
its own.

## Manifest (`location.json`, schema 1)

All numbers are ints. IDs match `^[A-Z0-9_]+$`.

| Field | Meaning |
|---|---|
| `schema`, `location_id`, `district_id` | `1`; the location ID that challenges name in `location_id`; the district |
| `name_key` | Text key of the location's player-facing name |
| `scene` | `res://…tscn` built from the layout by `tools/godot/build_district.gd -- --location=<dir>` |
| `files` | `{layout, dressing, look}`: file names in the same folder |
| `contracts` | Contract folders pinned here. Each must fit the location (below) |
| `grid.nodes` | `{id, kind, socket}`. `kind` is `source`, `junction` or `consumer`. `socket` is one of `{"building": id}` (a service building), `{"prop": id}`, `{"marker": id}`, or `{"feed": key}` (an off-site supply drawn by a dressing structure, such as the substation) |
| `grid.edges` | `{id, from, to}`: the cable routes the place physically has. They run from a source or junction to a junction or consumer |
| `landmarks` | `{ref: {building|prop: id}, role}`. `role` is `hero`, `secondary` or `base`. There is exactly one hero |
| `spawn.markers` | Four distinct `spawn` markers, one per crew member (1-4 players) |
| `spawn.opening_shot` | `from` (one of the spawns), `yaw_deg`, `pitch_deg`, `first_job` (`{building|prop|marker: id}`), `max_near_wall_percent` |
| `extraction.zone` | The layout zone the crew leaves from |
| `audit.backdrop` | Node paths under the built world that stand outside the envelope on purpose (the skyline) |

**Grid topology belongs to the place.** The location says where every node sits and which routes exist. A contract or
a challenge on the location uses a subset of those nodes and edges, with its own capacities, demands, faults and starting
state. A new challenge cannot invent a cable that the street does not have.

## Layout (`layout.json`)

The layout is the V01 district format, unchanged:
- integer centimetres;
- x east, z north, y up;
- 1 engine unit = 1 m.

`LocationData.layout()` adds the manifest's `scene` and `district_id` to it, so they are stated once.

| Rule | Check |
|---|---|
| Building sizes | Multiples of the 4 m module (`kit_dimensions.json` `module_cm`) |
| Corners, routes, prop footprints, kit placements | On the 25 cm placement grid |
| Envelope | Buildings, routes, props, zones and markers are inside it |
| Facades | Each listed face has one kit piece per module, every piece from `kit_pieces.json`. A face that is not listed is plain wall |
| Markers | Kind is `spawn`, `viewpoint`, `anchor`, `panel`, `switch` or `consumer` |
| IDs | Unique across buildings, routes, props, markers, zones and kit placements |

Marker IDs are the stable gameplay IDs. Nodes are built at fixed paths: `Markers/<id>`, `Zones/<id>`, `Props/<id>` and
`Buildings/<id>`. The host's range checks and the C01 contract use these paths.

## Validators

- **Python:** `tools/lbo_location.py`. It runs in `tools/run_tests.sh`.
- **GDScript:** `scripts/world/location_data.gd`. It needs no scene tree.

Both return `{code, message, ids}`. `tests/data/locations/cases.json` gives each case's codes, and both test suites run
all of them: `tests/python/test_rb02_location.py` and `tests/unit/test_RB02_location_format.gd`. Integer-only numbers are
checked for all content by `tools/validate_content.py`.

| Code | Meaning |
|---|---|
| `MISSING_FILE` | The manifest, a named file, or a pinned contract folder is missing or unreadable |
| `BAD_SCHEMA`, `INVALID_ID`, `BAD_VALUE` | Wrong schema, a malformed ID, or a malformed name key, scene path or backdrop |
| `BAD_LOOK` | The look has no profile file, environment overrides, palette or lamps |
| `BAD_LAYOUT`, `OFF_GRID`, `OUTSIDE_ENVELOPE`, `BAD_FACE`, `UNKNOWN_PIECE`, `BAD_MARKER`, `DUPLICATE_ID` | Layout rules (above) |
| `BAD_GRID`, `BAD_SOCKET` | Grid node kinds, edge directions, socket shape, or a consumer socket in a non-service building |
| `UNKNOWN_REF` | A socket, landmark, first job or extraction zone names something the location does not have |
| `BAD_LANDMARK` | A landmark is malformed, or there is not exactly one hero |
| `BAD_SPAWN` | There are not four distinct spawn markers, or the opening shot is malformed |

**Fit checks.** These check what is played on a location against the location itself.

`check_contract(location, contract_dir)` returns `CONTRACT_MISMATCH` when any of these fails:
- the contract's grid nodes and edges are inside the location's sockets and routes;
- its repair panels are `panel` markers;
- its switches are `switch` markers;
- its generator anchors are `anchor` markers at the same position;
- its recovery anchor is an `anchor` marker;
- its extraction zone is the location's extraction zone.

`check_challenge(location, challenge)` checks an RB03 challenge:
- it returns `WRONG_LOCATION` when `challenge.location_id` is a different location;
- it returns `CHALLENGE_MISMATCH` when the grid, fault panels, switches or temporary-supply anchors do not fit.

The fixture `tests/data/locations/alder_c01_challenge.json` is C01 converted by RB03's `from_contract()` and placed on
`ALDER_STREET`. It passes both checks. A test keeps it equal to the converter's output.

## Stage audit (`scripts/diagnostics/stage_audit.gd` `audit_location`)

The audit runs on the built, skinned and dressed world. That is the world the mission shows. The world must be in the
running SceneTree, so that physics queries can see it.

| Check | How |
|---|---|
| Nothing floats | The dispatch-stage support test: a mesh is held only if a chain of touching meshes reaches the ground. The backdrop is left out |
| Nothing leaves the envelope | Mesh centres stay within 0.5 m of the envelope. The backdrop is left out |
| Every target is reached | A 50 cm walk grid (`scripts/diagnostics/reach_grid.gd`, shared with the V01 probe) is searched from the opening spawn. Every `panel`, `switch` and `consumer` marker needs a connected cell from whose eye point the host's own sight check passes (`InteractionVisibility.can_reach`, interaction ray, selection radius). Every `anchor` needs a connected cell within 1 m on its floor |
| Spawns are clear | All four spawns are inside the site, standable, and a player capsule fits there |
| Opening shot | The eye is at the opening spawn, at the game camera's field of view (`offline_solo.json`), judged at 16:9. The hero landmark and the first job must each have at least 5 of 9 face points in frame and in plain sight. Non-floor surfaces within 3 m may cover at most `max_near_wall_percent` of a 32 × 18 ray grid |

The mission places the player at `spawn.opening_shot.from` and turns them to `yaw_deg`. The audit therefore judges the
frame the player actually gets.

## Adding a location (RB05 onward)

1. Copy the folder.
2. Write `location.json`, `layout.json`, `dressing.json` and `look.json`.
3. Run `python tools/lbo_location.py`.
4. Build the scene: `godot --headless --path . -s "$PWD/tools/godot/build_district.gd" -- --location=<dir>`.
5. Add the location to the audit test (`tests/integration/test_RB02_location_audit.gd` runs Alder Street today).
6. Capture the three-state set.

Still Alder-specific (RB05 should generalise these before a second location ships):
- The mission scene preloads `scenes/world/alder_street.tscn`.
- The DS10-DS12 presentations load the default location.
