extends RefCounted
## Detect the last intentional input device for localized, remapping-aware prompts.
## This does not replace InputMap and does not authorize any gameplay action.
## Ignore idle stick noise, key release, echo, and small mouse jitter to avoid
## flickering between keyboard/mouse and controller hints.

const UiText := preload("res://scripts/ui/ui_text.gd")
const STICK_THRESHOLD: float = 0.45
const MOUSE_MOTION_MIN_PIXELS: float = 3.0


static func infer(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		return UiText.DEVICE_PAD if (event as InputEventJoypadButton).pressed else ""
	if event is InputEventJoypadMotion:
		return UiText.DEVICE_PAD if absf((event as InputEventJoypadMotion).axis_value) >= STICK_THRESHOLD else ""
	if event is InputEventKey:
		var key: InputEventKey = event
		return UiText.DEVICE_KBM if key.pressed and not key.echo else ""
	if event is InputEventMouseButton:
		return UiText.DEVICE_KBM if (event as InputEventMouseButton).pressed else ""
	if event is InputEventMouseMotion:
		return UiText.DEVICE_KBM if (event as InputEventMouseMotion).relative.length() >= MOUSE_MOTION_MIN_PIXELS else ""
	return ""
