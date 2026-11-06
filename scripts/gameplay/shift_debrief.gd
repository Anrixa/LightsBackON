extends RefCounted
## Post-completion C01 scorecard. Reports only frozen, host-authored results.
## This presentation projection cannot issue rewards, change objectives, or
## infer hidden faults. Times use the authoritative 10 Hz mission clock.

const TICKS_PER_SECOND: int = 10
const MAX_STARS: int = 3


static func build(results: Dictionary) -> Dictionary:
	if results.is_empty():
		return {"available": false}

	var required_total: int = maxi(0, int(results.get("required_total", 0)))
	var required_restored: int = clampi(int(results.get("required_restored", 0)), 0, required_total)
	var optional_total: int = maxi(0, int(results.get("optional_total", 0)))
	var optional_ids: Array[String] = []
	var seen: Dictionary = {}
	var raw_optional: Variant = results.get("optional_services", [])
	if raw_optional is Array:
		for value: Variant in raw_optional:
			if not (value is String):
				continue
			var service_id: String = value
			# Content IDs are stable identifier tokens, never arbitrary UI text.
			if not service_id.is_valid_identifier() or service_id.length() > 64 or seen.has(service_id):
				continue
			seen[service_id] = true
			optional_ids.append(service_id)
	optional_ids.sort()
	var optional_restored: int = mini(optional_ids.size(), optional_total)
	var trips: int = maxi(0, int(results.get("trips", 0)))
	var preventable: int = clampi(int(results.get("preventable_trips", 0)), 0, trips)
	var recoveries: int = maxi(0, int(results.get("crew_recoveries", 0)))
	var ticks: int = maxi(0, int(results.get("ticks", 0)))

	var awards: Array[Dictionary] = [
		{"key": "offline.debrief.award_required",
			"earned": required_total > 0 and required_restored == required_total},
		{"key": "offline.debrief.award_optional",
			"earned": results.has("optional_total") and results.has("optional_services")
				and optional_restored == optional_total},
		{"key": "offline.debrief.award_protection",
			"earned": results.has("preventable_trips") and preventable == 0}
	]
	# The star total comes from the host, not from recomputing award flags.
	# A future contract can revise scoring without changing this UI projection.
	return {
		"available": true, "stars": clampi(int(results.get("stars", 0)), 0, MAX_STARS),
		"required_restored": required_restored, "required_total": required_total,
		"optional_restored": optional_restored, "optional_total": optional_total,
		"optional_services": optional_ids, "trips": trips,
		"preventable_trips": preventable, "recoveries": recoveries,
		"equipment_stowed": bool(results.get("equipment_collected", false)),
		"elapsed_ticks": ticks, "elapsed_clock": clock(ticks), "awards": awards
	}


## Minutes:seconds.tenths, with no wall-clock estimation or early rounding.
static func clock(ticks: int) -> String:
	var bounded: int = maxi(0, ticks)
	var seconds: int = floori(float(bounded) / float(TICKS_PER_SECOND))
	return "%02d:%02d.%d" % [floori(float(seconds) / 60.0),
		seconds % 60, bounded % TICKS_PER_SECOND]
