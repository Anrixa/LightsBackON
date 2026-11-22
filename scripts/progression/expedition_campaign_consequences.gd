extends RefCounted
## EXP020 A01 — durable *campaign* consequences derived exclusively from
## verified, existing EXP04 restoration receipts and the original A09 region tree.
## This is a strategic planning view, NOT live feeder voltage, reserve, fault,
## or cross-process runtime persistence. Nothing writes another save schema.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Campaign := preload("res://scripts/progression/expedition_campaign.gd")
const Networks := preload("res://scripts/gameplay/expedition_regional_network.gd")

const AUTHORITY: String = "EXP020_A01_EXISTING_RECEIPT_ONLY"
const QUALIFICATION: String = "STRATEGIC_SOURCE_ONLY_LIVE_ELECTRICAL_NOT_PERSISTED"


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "code": reason}


## Walk only NORMAL, original, receipt-restored feeders. Standby tie, switch
## state, reserve and electrical measurements are intentionally excluded:
## replaying a receipt must never claim that hardware is currently powered.
static func _receipt_connected(region: Dictionary, restored: Dictionary) -> Dictionary:
	var reached: Dictionary = {}
	var root: String = str(region["root_source_id"])
	if restored.has(root):
		reached[root] = true
	for pass_number: int in range(8):
		var changed: bool = false
		for feeder: Dictionary in region["primary_feeders"]:
			var upstream: String = str(feeder["from"])
			var downstream: String = str(feeder["to"])
			if reached.has(upstream) and restored.has(downstream) and not reached.has(downstream):
				reached[downstream] = true
				changed = true
		if not changed:
			break
	return reached


## Expected future planning benefit of restoring an AVAILABLE site, given
## already-bankable restoration receipts. This never adds or grants a receipt.
static func _gain(region: Dictionary, restored: Dictionary, site_id: String,
		original_reach: Dictionary) -> int:
	var projected: Dictionary = restored.duplicate()
	projected[site_id] = true
	var after: Dictionary = _receipt_connected(region, projected)
	var count: int = 0
	for key: String in after:
		if not original_reach.has(key):
			count += 1
	return count


static func evaluate(profile: Dictionary, atlas: Dictionary,
		routes: Dictionary, source_book: Dictionary) -> Dictionary:
	# Campaign.evaluate validates the profile against original EXP04 restoration
	# receipt IDs and original EXP05 OR-joins. Do not trust client flags.
	var board: Dictionary = Campaign.evaluate(profile, atlas, routes)
	if not bool(board.get("ok", false)):
		return board
	if source_book.get("authority") != Networks.SOURCE_AUTHORITY or 			source_book.get("qualification") != Networks.QUALIFICATION or 			not source_book.get("regions") is Array or 			(source_book["regions"] as Array).size() != Campaign.REGIONS:
		return _fail("REGIONAL_SOURCE_MISMATCH")
	var result: Dictionary = {}
	var total_restored: int = 0
	var total_ready: int = 0
	for region: Dictionary in source_book["regions"]:
		if not bool(Networks.inspect_region(atlas, region).get("ok", false)):
			return _fail("REGION_TOPOLOGY_INVALID")
		var id: String = str(region["region_id"])
		if result.has(id):
			return _fail("DUPLICATE_REGION")
		var restored: Dictionary = {}
		for site: Dictionary in region["source_sites"]:
			var site_id: String = str(site["site_id"])
			if not board["states"].has(site_id):
				return _fail("FOREIGN_REGION_SITE")
			if str(board["states"][site_id]["region_id"]) != id:
				return _fail("REGION_RECEIPT_IDENTITY")
			if str(board["states"][site_id]["status"]) == "RESTORED":
				restored[site_id] = true
		var reach: Dictionary = _receipt_connected(region, restored)
		var critical: String = str(region["critical_service_site"])
		var shelter: String = str(region["shelter_service_site"])
		var anchor: String = str(region["reserve_anchor_site"])
		var sites: Dictionary = {}
		var candidates: Array[Dictionary] = []
		for site: Dictionary in region["source_sites"]:
			var site_id: String = str(site["site_id"])
			var state: Dictionary = board["states"][site_id]
			var role: String = "critical_service" if site_id == critical else 				"shelter_service" if site_id == shelter else 				"reserve_anchor" if site_id == anchor else "ordinary_site"
			var potential: int = 0
			if state["status"] == "AVAILABLE":
				potential = _gain(region, restored, site_id, reach)
				candidates.append({"site_id": site_id, "priority": role,
					"new_receipt_connected_sites": potential,
					"location_name": site["location_name"]})
			sites[site_id] = {
				"status": state["status"], "priority_role": role,
				"restoration_receipt": restored.has(site_id),
				"normal_path_receipt_connected": reach.has(site_id),
				"potential_connected_gain": potential,
				"location_name": site["location_name"],
				"campaign_role": site["campaign_role"]
			}
		# Operational distinctions: a restored critical site still may not
		# have a receipt-connected normal path, and never implies live power.
		var critical_ready: bool = reach.has(critical)
		var shelter_ready: bool = reach.has(shelter)
		var state_label: String = "RECEIPT_PATH_TO_SHELTER" if shelter_ready else 			"CRITICAL_RECEIPT_PATH" if critical_ready else 			"PARTIAL_RECEIPT_PATH" if not reach.is_empty() else "NO_RECEIPT_PATH"
		result[id] = {
			"region_name": region["region_name"],
			"source_risk": region["risk_class"],
			"fault_signature": region["fault_signature"],
			"environment_hazard": region["environment_hazard"],
			"root_source_id": region["root_source_id"],
			"critical_service_site": critical, "shelter_service_site": shelter,
			"restored_receipts": restored.size(),
			"receipt_connected_sites": reach.size(),
			"critical_receipt_connected": critical_ready,
			"shelter_receipt_connected": shelter_ready,
			"status": state_label, "sites": sites,
			"available_priorities": candidates,
			"live_electrical_state_verified": false
		}
		total_restored += restored.size()
		total_ready += reach.size()
	if result.size() != Campaign.REGIONS or total_restored != int(board["restored"]):
		return _fail("CAMPAIGN_REGION_CARDINALITY")
	return {"ok": true, "authority": AUTHORITY, "qualification": QUALIFICATION,
		"regions": result, "restored_receipts": total_restored,
		"receipt_connected_sites": total_ready, "original_campaign_untouched": true}
