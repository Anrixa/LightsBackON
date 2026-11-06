extends RefCounted
## Read-only C01 shift dashboard. Everything comes from existing host-authored
## mission/equipment state; no client-side power, diagnosis or reward decisions.
## The view is ephemeral, so neither checkpoints nor the network protocol change.

const PUMP_LATCH_ID: String = "LATCH_PUMP_DRAIN"
const STATUS_DONE: String = "done"
const STATUS_ACTIVE: String = "active"


static func build(objectives: Array[Dictionary], mission_state: Dictionary, contract: Dictionary,
		equipment_stowed: bool, in_van_zone: bool, results: Dictionary = {}) -> Dictionary:
	var done: int = 0
	var active_key: String = ""
	var rows: Array[Dictionary] = []
	for objective: Dictionary in objectives:
		var status: String = str(objective.get("status", "pending"))
		var key: String = str(objective.get("text_key", ""))
		if status == STATUS_DONE:
			done += 1
		elif status == STATUS_ACTIVE and bool(objective.get("visible", false)) and active_key == "":
			active_key = key
		rows.append({"text_key": key, "status": status,
			"visible": bool(objective.get("visible", false))})

	var pump_total: int = 0
	for item: Variant in contract.get("access_latches", []):
		if item is Dictionary:
			var latch: Dictionary = item
			if str(latch.get("id", "")) == PUMP_LATCH_ID:
				pump_total = maxi(0, int(latch.get("supplied_ticks", 0)))
				break
	var latched: bool = (mission_state.get("latched", {}) as Dictionary).has(PUMP_LATCH_ID)
	var latch_ticks: Dictionary = mission_state.get("latch_ticks", {})
	var pump_ticks: int = pump_total if latched else clampi(int(latch_ticks.get(PUMP_LATCH_ID, 0)), 0, pump_total)
	var verify_total: int = maxi(0, int(contract.get("final_verification_ticks", 0)))
	var verify_ticks: int = clampi(int(mission_state.get("verify_ticks", 0)), 0, verify_total)
	var verified: bool = verify_total > 0 and verify_ticks >= verify_total
	var departure_total: int = maxi(0, int((contract.get("extraction", {}) as Dictionary).get("countdown_ticks", 0)))
	var departure_left: int = int(mission_state.get("countdown_left", -1))
	var departing: bool = departure_left >= 0
	var complete: bool = not results.is_empty()
	var ready: bool = verified and equipment_stowed and in_van_zone and not complete
	var phase_key: String = "offline.briefing.phase_restoring"
	if complete:
		phase_key = "offline.briefing.phase_complete"
	elif departing:
		phase_key = "offline.briefing.phase_departing"
	elif ready:
		phase_key = "offline.briefing.phase_ready"
	elif verified and not equipment_stowed:
		phase_key = "offline.briefing.phase_stow"
	elif verified:
		phase_key = "offline.briefing.phase_return"

	return {
		"objectives": rows, "objectives_done": done, "objectives_total": rows.size(),
		"active_key": active_key, "phase_key": phase_key,
		"pump_ticks": pump_ticks, "pump_total": pump_total, "pump_latched": latched,
		"pump_percent": percent(pump_ticks, pump_total),
		"verify_ticks": verify_ticks, "verify_total": verify_total,
		"verify_percent": percent(verify_ticks, verify_total), "verified": verified,
		"departure_left": departure_left, "departure_total": departure_total,
		"departure_percent": percent(departure_total - departure_left, departure_total) if departing else 0,
		"departing": departing, "ready": ready, "finished": complete,
		"equipment_stowed": equipment_stowed, "at_van": in_van_zone,
		"trips": maxi(0, int(mission_state.get("trips", 0))),
		"recoveries": maxi(0, int(mission_state.get("recoveries", 0)))
	}


static func percent(value: int, maximum: int) -> int:
	if maximum <= 0:
		return 0
	return clampi(roundi(100.0 * float(value) / float(maximum)), 0, 100)
