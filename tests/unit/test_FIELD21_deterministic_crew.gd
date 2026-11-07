extends "res://tests/test_case.gd"
## FIELD21: a read-only S06 crew task must not depend on dictionary insertion
## order. A participant can hold multiple repair locks; the HUD shows one
## deterministic representative rather than whichever peer snapshot iterated first.

const HudPresenter := preload("res://scripts/ui/hud_presenter.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")


func before_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)


func after_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)


static func _context() -> Dictionary:
	return {
		"local_player": "P1",
		"names": {"P1": "Local", "P2": "Partner"},
		"repairs": {"repairs": [
			{"id": "R_ZETA", "name_key": "repair.c01.west_fuse"},
			{"id": "R_ALPHA", "name_key": "repair.c01.east_trunk"}
		]},
		"equipment": {"equipment": [{"id": "GEN", "kind": "generator"}]}
	}


static func _state(locks: Dictionary, equipment: Dictionary = {}) -> Dictionary:
	return {
		"crew": ["P2", "P1"],
		"repairs": {"repairs": locks},
		"equipment": {"items": equipment}
	}


func test_FIELD21_lock_task_stable_when_network_dictionary_order_reverses() -> void:
	var first: Dictionary = {
		"R_ZETA": {"lock_owner": "P1"},
		"R_ALPHA": {"lock_owner": "P1"}
	}
	var reverse: Dictionary = {
		"R_ALPHA": {"lock_owner": "P1"},
		"R_ZETA": {"lock_owner": "P1"}
	}
	var a: Array[Dictionary] = HudPresenter.crew_rows(_state(first), _context())
	var b: Array[Dictionary] = HudPresenter.crew_rows(_state(reverse), _context())
	assert_eq(a, b, "the same authoritative locks must render the same crew task")
	assert_eq(a[0]["task_text"], UiText.t("repair.c01.east_trunk"),
		"the lowest stable repair ID is selected for a condensed chip")


func test_FIELD21_crew_order_is_local_then_stable_other_player() -> void:
	var locks: Dictionary = {"R_ZETA": {"lock_owner": "P2"}}
	var rows: Array[Dictionary] = HudPresenter.crew_rows(_state(locks), _context())
	assert_eq(rows.size(), 2)
	assert_eq(rows[0]["player"], "P1")
	assert_eq(rows[1]["player"], "P2")
	assert_eq(rows[0]["name"], "Local")
	assert_eq(rows[1]["name"], "Partner")
	assert_eq(rows[1]["task_text"], UiText.t("repair.c01.west_fuse"))


func test_FIELD21_active_repair_precedes_carried_equipment() -> void:
	var locks: Dictionary = {"R_ALPHA": {"lock_owner": "P1"}}
	var gear: Dictionary = {"GEN": {"carrier": "P1"}}
	var rows: Array[Dictionary] = HudPresenter.crew_rows(_state(locks, gear), _context())
	assert_eq(rows[0]["task_group"], "other")
	assert_eq(rows[0]["task_state"], "lock_owner")
	assert_eq(rows[0]["task_text"], UiText.t("repair.c01.east_trunk"),
		"the current repair is the more useful condensed task")


func test_FIELD21_carried_equipment_remains_visible_without_lock() -> void:
	var gear: Dictionary = {"GEN": {"carrier": "P1"}}
	var rows: Array[Dictionary] = HudPresenter.crew_rows(_state({}, gear), _context())
	assert_eq(rows[0]["task_group"], "equipment")
	assert_eq(rows[0]["task_state"], "generator")
	assert_eq(rows[0]["task_text"], UiText.t("equipment.generator"))


func test_FIELD21_empty_work_has_no_fabricated_task() -> void:
	var rows: Array[Dictionary] = HudPresenter.crew_rows(_state({}), _context())
	assert_false(rows[0].has("task_text"))
	assert_false(rows[1].has("task_text"))
	assert_false(rows[0].has("task_group"))


func test_FIELD21_carried_kind_stable_with_multiple_snapshot_items() -> void:
	# An abnormal snapshot cannot make the read-only tool label dependent on
	# serialization order. This does not authorize carrying extra equipment.
	var gear_a: Dictionary = {
		"ZZ_SPARE": {"carrier": "P1"},
		"GEN": {"carrier": "P1"}
	}
	var gear_b: Dictionary = {
		"GEN": {"carrier": "P1"},
		"ZZ_SPARE": {"carrier": "P1"}
	}
	var ctx: Dictionary = _context()
	var a: String = HudPresenter.carried_kind(_state({}, gear_a), "P1", ctx["equipment"])
	var b: String = HudPresenter.carried_kind(_state({}, gear_b), "P1", ctx["equipment"])
	assert_eq(a, "generator")
	assert_eq(a, b)
