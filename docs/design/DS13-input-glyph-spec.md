# DS13 — Input glyph design contract (Stormglass)

- **Status:** project-owned code implementation, physical visual signoff pending
- **Source of truth:** the current `InputMap.action_get_events(action)`; `InputDeviceTracker.infer(event)` identifies the last *intentional* device.
- **Purpose:** replace literal bracketed key strings with original keyboard, mouse and controller symbols without changing controls, input focus, save files or host authority.

## Original vector family

| Input source | Project-drawn shape | Interpretation |
|---|---|---|
| Physical or logical keyboard key | Flat charcoal rounded key cap, cool outline, Noto Sans key label | The first mapped key for that action; physical keys respect current OS layout where available |
| Mouse left/right/middle | Cool outlined mouse silhouette, coloured active half or wheel | Reads the actual mapped mouse button, never assumes the Interact key or mouse click |
| Mouse wheel | Same mouse body with centre wheel and directional mark | Actual mapped wheel direction, no hard-coded tool number |
| Generic gamepad A/B/X/Y | Circular face button, neutral label | Controller-family agnostic, no console platform branding/licensing |
| Gamepad shoulder / trigger / Menu / View | Extended slim capsule or key shape, abbreviated live label | Actual mapped shoulder or trigger, never guessed from action name |
| Gamepad D-pad | Four-arm cross with the mapped direction indicated | The true directional binding; not confused with a face button |
| Gamepad stick | Concentric thumb-stick circles and LS/RS text | Actual live joypad motion / stick click event |
| No compatible binding | Unbound key cap and localized text | Fail visibly rather than inventing E/A |

All paths are drawn via Godot `Control._draw()`, using `content/ui/tokens.json` and the approved Noto Sans font. No image downloads, branded silhouettes, licensed audio, binary assets or imported fonts.

## Runtime surfaces

- **Field HUD:** targeted interact prompt plus Network Tablet and Ping action hints.
- **Network Tablet:** inspectable panel, live Ping action and Close footer. The original focusable buttons remain; glyphs have `MOUSE_FILTER_IGNORE` and `FOCUS_NONE`.
- **First repair onboarding:** paired glyph strip reflects the actual tutorial actions for the current device. Visible instructions retain descriptive localized text for screen readers; a hint glyph sits beside the unchanged action button.
- **Main Menu:** six action-labelled glyphs replace stale hard-coded WASD/E/A/TAB help. The HFlowContainer wraps at smaller viewports and follows remapped keys and the last intentional device.
- **Input remapping:** `InputGlyph.refresh_binding()` reads the original action, compares the new semantic descriptor, updates visual and tooltip only when a binding actually changes. Visible glyphs poll at most four times per second and do not create an input interceptor.
- **Device switching:** the pre-existing `InputDeviceTracker` rejects key releases, key echo, stick drift and mouse jitter. Mission HUD, tablet and onboarding already receive its device changes; DS13 adds the same approach to the menu.
- **Localization:** text-only screen-reader fallback remains in labels, and all added captions are localized. The pseudo-locale continues to exercise 35% expansion.

## Non-goals and locked gates

- Does not implement an in-game keybinding editor, change OS keyboard layouts or store custom bindings; it reflects any live `InputMap` remap.
- Does not modify the authority graph, RPCs, physics, achievements, persistence or matchmaking.
- Do not claim real-world readability, color-blind AA rendered contrast, gamepad ergonomics or keyboard layout coverage without physical evidence. Capture 720p/1080p at 80/100/150%, controller-only walkthrough, custom physical-key remaps and GPU screen samples after cloud merge.
- Keep DS14 tool/hand art and F02/F06/V09 gates independent.

## Batch implementation and verification

Read `docs/evidence/DS13.md`, `docs/design/quality-workstream.json` and `docs/design/BATCH-EXECUTION-HANDOFF.md` for source/CI checkpoint and owner-approved substantial-batch test cadence.
