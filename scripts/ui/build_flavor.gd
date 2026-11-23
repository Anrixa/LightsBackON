extends RefCounted
## Internal vs release build (ADR-019 point 4, CLAUDE.md section 9: debug tools only in internal exports).
## An internal build is the "Windows Desktop (internal)" export (custom feature "internal") or the editor binary.
## Release-only player screens (the main menu without the dispatch atlas, no engineering overlay) are decided here, in one
## place. Tests and the RB01 release text check call simulate_release(true) to see exactly what a release export shows,
## because they themselves run on the editor binary.

static var _simulate_release: bool = false


static func is_internal() -> bool:
	if _simulate_release:
		return false
	return OS.has_feature("internal") or OS.has_feature("editor")


## Test and release-check hook only. It can make an internal build behave like a release build, never the reverse.
static func simulate_release(on: bool) -> void:
	_simulate_release = on


static func simulating_release() -> bool:
	return _simulate_release
