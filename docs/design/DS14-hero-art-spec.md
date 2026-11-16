# DS14 — First-person equipment and hero-asset art contract

- Phase: DS14, under the DS08-approved Stormglass / Civic Revival visual language.
- Scope: original project-made geometry only; no purchased/downloaded assets, real logos, character IP, textures or shader plugins.
- Production presentation sources: `scripts/world/hero_prop_builder.gd`, `scripts/actors/first_person_equipment.gd`, `scripts/world/generator_tradeoff_presentation.gd`, `scripts/actors/first_person_controller.gd`, `scripts/gameplay/mission_root.gd`.
- Non-shipping design review: `scenes/lookdev/ds14_hero_gallery.tscn` with `scripts/world/ds14_asset_gallery.gd`.
- Original colour and dimension manifest: `assets/design/ds14_hero_art.json`. **Do not move to `content/`**: existing C01 checkpoint hashes include `content/` recursively; art-only changes must not silently invalidate saves (DS08 finding).

## Real runtime behaviour

1. A noninteractive gloved two-hand model and one of five original tool silhouettes are children of the existing local player's **Eyes** camera: meter, screwdriver, puller, cutter and crimper.
2. A switch only changes which already-built model is visible. It follows the authoritative local session's selected tool, including restored checkpoints and key/controller tool-slot changes. Unknown tool IDs fail closed: no guessed model.
3. The locally carried portable generator hides the handheld prop but not the gloves. Camera bob and accessibility remain controlled only by the existing A04 player controller, not by new code. Hands and tools do not intercept mouse, gamepad or keyboard events.
4. The DS11 generator receives a transport frame, two wheels, vents, markings and a cable reel. This art is under the **same node already hidden or placed by `GeneratorTradeoffPresentation.apply`**. Its current PU load/trip warning/sound and authored cable-route visibility still come entirely from the host.
5. Three outfit variants—field, line, supervisor—are built for a standalone non-shipping review gallery. **They are not fictional multiplayer peers** and never appear as supply, repair or crew data.

## Implementation guardrails

- Godot 4.7.2 standard / Compatibility renderer. StandardMaterial3D and low-polygon Box, Cylinder and Sphere meshes only. No dynamic lights, expensive geometry instancing, collisions, ray targets, network channels or saved fields.
- The existing `scenes/actors/worker_silhouette.tscn` is left byte-identical (the kit generator owns it). Gallery rigs are an add-on rather than a replacement for the fixed F05 acceptance model.
- Every colour is supplied by the original manifest. Use shared materials within each builder instance, with no assets downloaded.
- Screen performance and polish are **not** certified by source or headless tests. Real Windows 720p/1080p captures, hand/target occlusion, generated geometry silhouette/contrast, true controller operation and Intel UHD/GTX 1650 exported frame P95/memory must be checked separately.

## Asset provenance

| Family | Source | Creator | Rights |
|---|---|---|---|
| Five tool meshes + first-person gloved arms | `hero_prop_builder.gd`, `ds14_hero_art.json` | Original Lights Back On project creation, 16 Nov 2026 | Project-owned |
| Generator frame, wheels, vents and reel | Same builder; mounted in `generator_tradeoff_presentation.gd` | Same | Project-owned |
| Field/line/supervisor worker preview rigs | Same builder, `ds14_asset_gallery.gd` | Same | Project-owned |

No binary imports and no external asset creator/license are involved. No production art certification is asserted before the local screen review.
