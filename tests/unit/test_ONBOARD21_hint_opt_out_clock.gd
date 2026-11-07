extends "res://tests/test_case.gd"
## ONBOARD21: optional hints must not accrue invisible idle time when disabled
## or jump straight to a high-tier hint when the player re-enables them.

const GuideCard := preload("res://scripts/ui/onboarding_card.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")


func before_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)


func after_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)


func test_ONBOARD21_disabled_hints_do_not_accrue_idle_time() -> void:
	var card: PanelContainer = GuideCard.new()
	card.call("set_hints_enabled", false)
	card.call("advance_idle", 180.0)
	assert_eq((card.get("hint") as Label).text, "",
		"turning off optional hints prevents unsolicited help")
	card.call("set_hints_enabled", true)
	card.call("advance_idle", 19.9)
	assert_eq((card.get("hint") as Label).text, "",
		"hidden disabled time must not count toward the next hint")
	card.call("advance_idle", 0.1)
	assert_eq((card.get("hint") as Label).text, UiText.t("guide.hint.move.1"),
		"freshly enabled help starts at the first tier")
	card.free()


func test_ONBOARD21_reenable_after_visible_hint_resets_tier() -> void:
	var card: PanelContainer = GuideCard.new()
	card.call("advance_idle", 95.0)
	assert_eq((card.get("hint") as Label).text, UiText.t("guide.hint.move.3"))
	card.call("set_hints_enabled", false)
	assert_eq((card.get("hint") as Label).text, "", "the old hint disappears immediately")
	assert_true((card.get("hint_button") as Button).disabled)
	card.call("advance_idle", 120.0)
	card.call("set_hints_enabled", true)
	assert_false((card.get("hint_button") as Button).disabled)
	card.call("advance_idle", 19.9)
	assert_eq((card.get("hint") as Label).text, "")
	card.call("advance_idle", 0.1)
	assert_eq((card.get("hint") as Label).text, UiText.t("guide.hint.move.1"),
		"re-enabled hints must not skip to the later tier")
	card.free()


func test_ONBOARD21_repeated_settings_refresh_preserves_manual_help() -> void:
	var card: PanelContainer = GuideCard.new()
	card.call("show_hint")
	assert_eq((card.get("hint") as Label).text, UiText.t("guide.hint.move.1"))
	card.call("set_hints_enabled", true)
	assert_eq((card.get("hint") as Label).text, UiText.t("guide.hint.move.1"),
		"re-applying an unchanged setting must not erase requested help")
	card.free()


func test_ONBOARD21_guide_progression_still_resets_idle_tier() -> void:
	var card: PanelContainer = GuideCard.new()
	card.call("advance_idle", 90.0)
	card.call("observe", "player_moved")
	assert_eq((card.get("hint") as Label).text, "")
	card.call("advance_idle", 20.0)
	assert_eq((card.get("hint") as Label).text, UiText.t("guide.hint.measure.1"),
		"genuine progression still opens the next instruction's first hint")
	card.free()


func test_ONBOARD21_manual_help_is_available_after_enable() -> void:
	var card: PanelContainer = GuideCard.new()
	card.call("set_hints_enabled", false)
	card.call("show_hint")
	assert_eq((card.get("hint") as Label).text, "")
	card.call("set_hints_enabled", true)
	card.call("show_hint")
	assert_eq((card.get("hint") as Label).text, UiText.t("guide.hint.move.1"),
		"re-enable restores manual help without automatically disclosing hints")
	card.free()
