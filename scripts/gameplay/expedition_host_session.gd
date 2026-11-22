extends RefCounted
## EXP03: host-only expedition session for the 200 authored dispatches.
##
## Every client action goes through the production SessionHost.receive() byte
## envelope and the original Grid/Meter/Interaction/Equipment/Mission services.
## Task advancement observes accepted host evidence; never trusts client claims
## of progress, location, rewards, inspection results, or clock time.
##
## The caller must supply a SERVER-OWNED character position provider, not a
## client-reported transform. This source/headless service has no collision
## world; the later physical scene integration must add sight/capsule checks.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Plan := preload("res://scripts/world/expedition_layout_plan.gd")
const Factory := preload("res://scripts/gameplay/expedition_contract_factory.gd")
const Grid := preload("res://scripts/simulation/power_grid.gd")
const Meter := preload("res://scripts/simulation/meter_model.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const Equipment := preload("res://scripts/interaction/equipment_service.gd")
const Mission := preload("res://scripts/simulation/mission_director.gd")
const Host := preload("res://scripts/network/session_host.gd")
const Rewards := preload("res://scripts/progression/reward_service.gd")
const Ledger := preload("res://scripts/progression/expedition_ledger.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")
const Campaign := preload("res://scripts/progression/expedition_campaign.gd")
const Bespoke := preload("res://scripts/gameplay/expedition_bespoke_mechanics.gd")
const Devices := preload("res://scripts/gameplay/expedition_device_graph.gd")
const Faults := preload("res://scripts/gameplay/expedition_fault_diagnostics.gd")
const Consequences := preload("res://scripts/gameplay/expedition_consequences.gd")
const Logistics := preload("res://scripts/gameplay/expedition_emergency_logistics.gd")
const Balancing := preload("res://scripts/gameplay/expedition_critical_loads.gd")
const Worksite := preload("res://scripts/gameplay/expedition_worksite_orders.gd")
const SiteA02 := preload("res://scripts/gameplay/expedition_site_interventions.gd")
const SiteEXP013 := preload("res://scripts/gameplay/expedition_site_exp013.gd")
const SiteContingencies := preload("res://scripts/gameplay/expedition_site_contingencies.gd")
const SiteApproach := preload("res://scripts/gameplay/expedition_approach_intelligence.gd")
const SiteOutcomes := preload("res://scripts/gameplay/expedition_operational_consequences.gd")
const SiteHazards := preload("res://scripts/gameplay/expedition_environment_hazards.gd")
const SitePuzzles := preload("res://scripts/gameplay/expedition_investigation_chains.gd")
const AdvancedDiscoveries := preload("res://scripts/gameplay/expedition_advanced_discoveries.gd")
const AdvancedCascade := preload("res://scripts/gameplay/expedition_advanced_cascade.gd")
const AdvancedPolicies := preload("res://scripts/gameplay/expedition_advanced_policies.gd")
const AdvancedEquipment := preload("res://scripts/gameplay/expedition_advanced_equipment.gd")
const AdvancedHazards := preload("res://scripts/gameplay/expedition_advanced_hazards.gd")
const AdvancedFaults := preload("res://scripts/gameplay/expedition_advanced_fault_layers.gd")
const AdvancedCases := preload("res://scripts/gameplay/expedition_advanced_casework.gd")
const RegionalNetworks := preload("res://scripts/gameplay/expedition_regional_network.gd")
const OfflinePersistence := preload("res://scripts/persistence/offline_persistence.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")

const RUNTIME_SCHEMA: int = 1
const PROTOCOL: int = 1
const PLAYER_ID: String = "P1"
const TOOLS: Array[String] = ["meter", "screwdriver", "puller", "cutter", "crimper"]
const INTERACTION_REACH_M: float = 2.30
const PANEL_RADIUS_M: float = 0.48
const SWITCH_RADIUS_M: float = 0.34
const EXTRACTION_RADIUS_M: float = 1.50

var grid: Grid
var meter: Meter
var interaction: Interaction
var equipment: Equipment
var mission: Mission
var host: Host
var bespoke: Bespoke
var devices: Devices
var faults: Faults
var consequences: Consequences
var logistics: Logistics
var balancing: Balancing
var worksite: Worksite
var site_a02: SiteA02
var site_exp013: SiteA02
var site_contingency: SiteContingencies
var site_approach: SiteApproach
var site_outcomes: SiteOutcomes
var site_hazards: SiteHazards
var site_puzzles: SitePuzzles
var advanced_cascade: AdvancedCascade
var advanced_cases: AdvancedCases
var regional_network: RegionalNetworks

var _definitions: Dictionary = {}
var _position_source: Callable
var _physics_visibility: Callable
var _tasks: Array[Dictionary] = []
var _completed: Dictionary = {}
var _observed_inspections: Dictionary = {}
var _tick: int = 0
var _ready: bool = false
var _collectible: Dictionary = {}
var _lore_claimed: bool = false
var _account_key: String = ""
var _issued: Dictionary = {}
var _reward_queue: Rewards.HostQueue = Rewards.HostQueue.new()


static func _json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


static func _fail(code: String, details: Variant = null) -> Dictionary:
	return {"ok": false, "code": code, "details": details}


## Only source-pinned ID selection is accepted. Reject a forged catalog or
## invalid geometry before constructing a single authority-bearing service.
func start(level_id: String, host_position: Callable,
		physics_visibility: Callable = Callable(), account_key: String = "",
		enforce_campaign: bool = false, campaign_root: String = "",
		enable_bespoke: bool = false, enable_devices: bool = false,
		enable_faults: bool = false, enable_consequences: bool = false,
		enable_logistics: bool = false, enable_balance: bool = false,
		enable_worksite: bool = false, enable_site_a02: bool = false,
		enable_site_exp013: bool = false,
		enable_site_contingency: bool = false,
		enable_site_approach: bool = false,
		enable_site_outcomes: bool = false,
		enable_site_hazards: bool = false,
		enable_site_puzzles: bool = false,
		enable_regional_networks: bool = false,
		enable_advanced_cases: bool = false,
		enable_advanced_fault_layers: bool = false,
		enable_advanced_environment: bool = false,
		enable_advanced_equipment: bool = false,
		enable_advanced_policy: bool = false,
		enable_advanced_cascade: bool = false,
		enable_advanced_discoveries: bool = false) -> Dictionary:
	if _ready:
		return _fail("SESSION_ALREADY_STARTED")
	if enable_devices and not enable_bespoke:
		return _fail("EXP07_REQUIRES_EXP06")
	if enable_faults and not enable_devices:
		return _fail("EXP08_REQUIRES_EXP07")
	if enable_consequences and not enable_faults:
		return _fail("EXP009_REQUIRES_EXP08")
	if enable_logistics and not enable_consequences:
		return _fail("EXP010_REQUIRES_EXP009")
	if enable_balance and not enable_logistics:
		return _fail("EXP011_REQUIRES_EXP010")
	if enable_worksite and not enable_balance:
		return _fail("EXP012_REQUIRES_EXP011")
	if enable_site_a02 and not enable_worksite:
		return _fail("EXP012A02_REQUIRES_EXP012")
	if enable_site_exp013 and not enable_worksite:
		return _fail("EXP013_REQUIRES_EXP012")
	if enable_site_contingency and (not enable_site_a02 or not enable_site_exp013):
		return _fail("EXP014_REQUIRES_EXP012A02_AND_EXP013")
	if enable_site_approach and not enable_site_contingency:
		return _fail("EXP014_A05_REQUIRES_A02_CONTINGENCY")
	if enable_site_outcomes and not enable_site_approach:
		return _fail("EXP014_A06_REQUIRES_A05_RECON")
	if enable_site_hazards and not enable_site_outcomes:
		return _fail("EXP014_A07_REQUIRES_A06_OUTCOMES")
	if enable_site_puzzles and not enable_site_hazards:
		return _fail("EXP014_A08_REQUIRES_A07_ENVIRONMENT")
	if enable_advanced_discoveries and not enable_advanced_policy:
		return _fail("EXP016_A11_REQUIRES_A09_SOURCE_POLICY")
	if enable_advanced_cascade and (not enable_advanced_policy or \
			not enable_regional_networks or not enforce_campaign or account_key == ""):
		return _fail("EXP016_A10_REQUIRES_AUTHENTICATED_REGIONAL_CAMPAIGN")
	if enable_advanced_policy and not enable_advanced_equipment:
		return _fail("EXP016_A09_REQUIRES_A08_AUTHENTICATED_GEAR")
	if enable_advanced_equipment and not enable_advanced_environment:
		return _fail("EXP016_A08_REQUIRES_A07_HAZARD_INTERLOCK")
	if enable_advanced_environment and not enable_advanced_fault_layers:
		return _fail("EXP016_A07_REQUIRES_A06_HOST_FAULT_AUTHORITY")
	if enable_advanced_fault_layers and not enable_advanced_cases:
		return _fail("EXP016_A06_REQUIRES_ADVANCED_CASE_AUTHORITY")
	if enable_advanced_cases and not enable_site_puzzles:
		return _fail("EXP016_A02_REQUIRES_A08_HOST_INVESTIGATION")
	if enable_regional_networks and (not enable_site_puzzles or not enforce_campaign):
		return _fail("EXP014_A09_REQUIRES_A08_AND_HOST_CAMPAIGN")
	if account_key != "" and not SaveService.is_valid_key(account_key):
		return _fail("INVALID_ACCOUNT_KEY")
	if not host_position.is_valid() or (physics_visibility.is_valid() and not host_position.is_valid()):
		return _fail("MISSING_HOST_POSITION")
	var atlas: Dictionary = Atlas.load_catalog()
	var audit: Dictionary = Atlas.inspect(atlas)
	if not bool(audit.get("ok", false)):
		return _fail("ATLAS_SOURCE_INVALID", audit.get("failures", []))
	var level: Dictionary = Atlas.find_level(atlas, level_id)
	if level.is_empty():
		return _fail("UNKNOWN_LEVEL")
	# EXP05 host-gated dispatch is opt-in; legacy source/headless sessions with
	# no campaign requirement retain their existing EXP03/EXP04 semantics.
	# The profile is read by the host, never supplied in the network envelope.
	if enforce_campaign:
		if account_key == "":
			return _fail("CAMPAIGN_IDENTITY_REQUIRED")
		var saves: SaveService = SaveService.new()
		saves.configure(1, OfflinePersistence.SAVE_BUILD_ID,
			ContentHash.content_revision(), ContentHash.rules_revision())
		var root: String = OfflinePersistence.runtime_root() if campaign_root == "" else campaign_root
		var loaded: Dictionary = Ledger.load_profile(saves, account_key, root)
		if not bool(loaded.get("ok", false)):
			return _fail("CAMPAIGN_PROFILE_HOLD", loaded)
		var access: Dictionary = Campaign.can_launch(loaded["profile"], atlas,
			Campaign.load_routes(), level_id)
		if not bool(access.get("ok", false)):
			return _fail(str(access.get("code", "CAMPAIGN_ROUTE_INVALID")), access)
		if enable_regional_networks:
			# No client progress flag: host loads independently verified EXP04 receipts.
			var regional_gate: Dictionary = RegionalNetworks.acquire(
				atlas, loaded["profile"], level_id)
			if not bool(regional_gate.get("ok", false)):
				return _fail("EXP014_A09_REGIONAL_PROFILE_HOLD", regional_gate)
			regional_network = regional_gate["network"]
	var location: Dictionary = Atlas.find_location(atlas, str(level["location_id"]))
	var plan: Dictionary = Plan.make_plan(level, location)
	_definitions = Factory.build(level, plan)
	if regional_network != null:
		_definitions["regional_network"] = regional_network.snapshot()
	if not bool(_definitions.get("ok", false)):
		return _fail("CONTRACT_FACTORY_FAILED", _definitions)
	if enable_bespoke:
		var book: Dictionary = Bespoke.load_book()
		var integrity: Dictionary = Bespoke.inspect(atlas, book)
		if not bool(integrity.get("ok", false)):
			return _fail("EXP06_BOOK_INVALID", integrity)
		var encounter: Dictionary = Bespoke.entry_for(book, level, location)
		if encounter.is_empty():
			return _fail("EXP06_ENCOUNTER_SOURCE_MISMATCH")
		bespoke = Bespoke.new()
		var activated: Dictionary = bespoke.configure(encounter)
		if not bool(activated.get("ok", false)):
			return _fail("EXP06_CONFIG_FAILED", activated)
		_definitions["bespoke"] = bespoke.definition_snapshot()
	if enable_devices:
		var device_book: Dictionary = Devices.load_book()
		var device_audit: Dictionary = Devices.inspect(atlas, Bespoke.load_book(), device_book)
		if not bool(device_audit.get("ok", false)):
			return _fail("EXP07_BOOK_INVALID", device_audit)
		var graph: Dictionary = Devices.entry_for(device_book, level, bespoke.definition_snapshot())
		if graph.is_empty():
			return _fail("EXP07_SOURCE_MISMATCH")
		devices = Devices.new()
		var config: Dictionary = devices.configure(graph)
		if not bool(config.get("ok", false)):
			return _fail("EXP07_DEVICE_CONFIG_FAILED", config)
		_definitions["devices"] = devices.definition_snapshot()
		# Five or six individually source-pinned physical targets per level.
		# These are source-engineering markers, not route/playability certification.
		for device: Dictionary in graph["nodes"]:
			var anchor: String = str(device["anchor"])
			var base: Vector3 = _definitions["positions"][anchor]
			(_definitions["positions"] as Dictionary)[str(device["id"])] = \
				base + Vector3(0.85, 0.0, 0.55)
	if enable_faults:
		var fault_book: Dictionary = Faults.load_book()
		var fault_audit: Dictionary = Faults.inspect(atlas, Devices.load_book(), fault_book)
		if not bool(fault_audit.get("ok", false)):
			return _fail("EXP08_BOOK_INVALID", fault_audit)
		var scenario: Dictionary = Faults.entry_for(fault_book, level, devices.definition_snapshot())
		if scenario.is_empty():
			return _fail("EXP08_SOURCE_MISMATCH")
		faults = Faults.new()
		var fault_config: Dictionary = faults.configure(scenario)
		if not bool(fault_config.get("ok", false)):
			return _fail("EXP08_CONFIG_FAILED", fault_config)
		_definitions["faults"] = faults.definition_snapshot()
		for target: String in ["probe_a", "probe_b", "console"]:
			var anchor: String = str(scenario["anchors"][target])
			var offset: Vector3 = Vector3(-0.85, 0.0, -0.52) if target != "console" else Vector3(-0.65, 0.0, 0.70)
			(_definitions["positions"] as Dictionary)[str(scenario[target])] = \
				(_definitions["positions"] as Dictionary)[anchor] + offset
	if enable_consequences:
		var chain_book: Dictionary = Consequences.load_book()
		var chain_audit: Dictionary = Consequences.inspect(atlas, Faults.load_book(), chain_book)
		if not bool(chain_audit.get("ok", false)):
			return _fail("EXP009_BOOK_INVALID", chain_audit)
		var chain: Dictionary = Consequences.entry_for(chain_book, level, faults.definition_snapshot())
		if chain.is_empty():
			return _fail("EXP009_SOURCE_MISMATCH")
		consequences = Consequences.new()
		var chain_config: Dictionary = consequences.configure(chain)
		if not bool(chain_config.get("ok", false)):
			return _fail("EXP009_CONFIG_FAILED", chain_config)
		_definitions["consequences"] = consequences.definition_snapshot()
		for node: Dictionary in chain["nodes"]:
			var anchor: String = str(node["anchor"])
			(_definitions["positions"] as Dictionary)[str(node["id"])] = \
				(_definitions["positions"] as Dictionary)[anchor] + Vector3(0.0, 0.0, -0.9)
		(_definitions["positions"] as Dictionary)[str(chain["console"])] = \
			(_definitions["positions"] as Dictionary)[str(chain["console_anchor"])] + Vector3(0.70, 0.0, 0.60)
	if enable_logistics:
		var logistics_book: Dictionary = Logistics.load_book()
		var logistics_audit: Dictionary = Logistics.inspect(atlas, Consequences.load_book(), logistics_book)
		if not bool(logistics_audit.get("ok", false)):
			return _fail("EXP010_BOOK_INVALID", logistics_audit)
		var manifest: Dictionary = Logistics.entry_for(logistics_book, level,
			consequences.definition_snapshot())
		if manifest.is_empty():
			return _fail("EXP010_SOURCE_MISMATCH")
		logistics = Logistics.new()
		var logistics_config: Dictionary = logistics.configure(manifest)
		if not bool(logistics_config.get("ok", false)):
			return _fail("EXP010_CONFIG_FAILED", logistics_config)
		_definitions["logistics"] = logistics.definition_snapshot()
		var positions: Dictionary = _definitions["positions"]
		positions[str(manifest["depot"])] = positions[str(manifest["depot_anchor"])] + Vector3(1.25, 0.0, 0.65)
		positions[str(manifest["console"])] = positions[str(manifest["console_anchor"])] + Vector3(1.35, 0.0, -0.75)
		for job: Dictionary in manifest["jobs"]:
			positions[str(job["id"])] = positions[str(job["anchor"])] + Vector3(-1.25, 0.0, 0.70)
	if enable_balance:
		var balance_book: Dictionary = Balancing.load_book()
		var balance_audit: Dictionary = Balancing.inspect(atlas, Logistics.load_book(), balance_book)
		if not bool(balance_audit.get("ok", false)):
			return _fail("EXP011_BOOK_INVALID", balance_audit)
		var board: Dictionary = Balancing.entry_for(balance_book, level, logistics.definition_snapshot())
		if board.is_empty():
			return _fail("EXP011_SOURCE_MISMATCH")
		balancing = Balancing.new()
		var balanced: Dictionary = balancing.configure(board)
		if not bool(balanced.get("ok", false)):
			return _fail("EXP011_CONFIG_FAILED", balanced)
		_definitions["balancing"] = balancing.definition_snapshot()
		var load_positions: Dictionary = _definitions["positions"]
		load_positions[str(board["board"])] = load_positions[str(board["board_anchor"])] + Vector3(1.65, 0.0, -0.75)
		load_positions[str(board["console"])] = load_positions[str(board["console_anchor"])] + Vector3(-1.65, 0.0, -0.75)
		for j: int in range(3):
			var service: Dictionary = board["services"][j]
			var offset: Vector3 = [Vector3(1.45, 0.0, 0.60), Vector3(-1.45, 0.0, 0.60),
				Vector3(-1.50, 0.0, 0.75)][j]
			load_positions[str(service["id"])] = load_positions[str(service["anchor"])] + offset
	if enable_worksite:
		var worksite_book: Dictionary = Worksite.load_book()
		var worksite_audit: Dictionary = Worksite.inspect(atlas, Balancing.load_book(), worksite_book)
		if not bool(worksite_audit.get("ok", false)):
			return _fail("EXP012_BOOK_INVALID", worksite_audit)
		var order: Dictionary = Worksite.entry_for(worksite_book, level,
			balancing.definition_snapshot())
		if order.is_empty():
			return _fail("EXP012_SOURCE_MISMATCH")
		worksite = Worksite.new()
		var worksite_config: Dictionary = worksite.configure(order)
		if not bool(worksite_config.get("ok", false)):
			return _fail("EXP012_CONFIG_FAILED", worksite_config)
		_definitions["worksite"] = worksite.definition_snapshot()
		var work_positions: Dictionary = _definitions["positions"]
		work_positions[str(order["board"])] = work_positions[str(order["anchors"]["board"])] + Vector3(0.75, 0.0, 1.35)
		work_positions[str(order["decision"])] = work_positions[str(order["anchors"]["decision"])] + Vector3(-0.75, 0.0, 1.20)
		work_positions[str(order["console"])] = work_positions[str(order["anchors"]["console"])] + Vector3(0.75, 0.0, 1.35)
		work_positions[str(order["optional_target"])] = work_positions[str(order["anchors"]["optional_target"])] + Vector3(0.75, 0.0, -1.35)
		for j: int in range(3):
			var checkpoint: Dictionary = order["checkpoints"][j]
			var offset: Vector3 = [Vector3(-1.20, 0.0, -1.30),
				Vector3(1.20, 0.0, 1.30), Vector3(1.25, 0.0, -1.30)][j]
			work_positions[str(checkpoint["id"])] = work_positions[str(checkpoint["anchor"])] + offset
	# The A02 overlay is available only for the 40 explicitly authored
	# source-linked locations. The other 160 remain unchanged A01 sessions.
	if enable_site_a02:
		var authored: Dictionary = SiteA02.load_book()
		var review: Dictionary = SiteA02.inspect(atlas, Worksite.load_book(), authored)
		if not bool(review.get("ok", false)):
			return _fail("EXP012A02_BOOK_INVALID", review)
		var site_case: Dictionary = SiteA02.entry_for(authored, level,
			worksite.definition_snapshot())
		if not site_case.is_empty():
			site_a02 = SiteA02.new()
			var configured: Dictionary = site_a02.configure(site_case)
			if not bool(configured.get("ok", false)):
				return _fail("EXP012A02_CONFIG_FAILED", configured)
			_definitions["site_a02"] = site_a02.definition_snapshot()
			var site_positions: Dictionary = _definitions["positions"]
			# Three physical targets; actual collision/path accessibility is held.
			site_positions[str(site_case["targets"]["A"])] = \
				site_positions["PANEL_WEST"] + Vector3(1.65, 0.0, 1.45)
			site_positions[str(site_case["targets"]["B"])] = \
				site_positions["PANEL_SPUR"] + Vector3(-1.65, 0.0, 1.45)
			site_positions[str(site_case["targets"]["C"])] = \
				site_positions["R_WEST"] + Vector3(-1.65, 0.0, 1.45)
	# EXP013 A01 is a second, disjoint, opt-in source book (LV_041–LV_080).
	# The A02 machine remains unmodified; the new content is independently audited
	# and receives its own host state, revision namespace and extraction interlock.
	if enable_site_exp013:
		var exp013_books: Array[Dictionary] = SiteEXP013.load_available_books()
		var exp013_audit: Dictionary = SiteEXP013.inspect_collection(
			atlas, Worksite.load_book(), exp013_books)
		if not bool(exp013_audit.get("ok", false)):
			return _fail("EXP013_BOOK_INVALID", exp013_audit)
		# Exactly one source-pinned level may be selected. Earlier opt-in
		# sessions and all uncovered 200-level foundation sites remain unchanged.
		var exp013_case: Dictionary = {}
		for source_book: Dictionary in exp013_books:
			var matching: Dictionary = SiteEXP013.entry_for(source_book, level,
				worksite.definition_snapshot())
			if not matching.is_empty():
				if not exp013_case.is_empty():
					return _fail("EXP013_OVERLAPPING_BOOKS")
				exp013_case = matching
				_definitions["site_exp013_phase"] = str(source_book["authority"]).split("_")[1]
		if not exp013_case.is_empty():
			if site_a02 != null:
				return _fail("EXP013_OVERLAPPING_SITE_BOOKS")
			site_exp013 = SiteA02.new()
			var configured: Dictionary = site_exp013.configure(exp013_case)
			if not bool(configured.get("ok", false)):
				return _fail("EXP013_CONFIG_FAILED", configured)
			_definitions["site_exp013"] = site_exp013.definition_snapshot()
			var exp013_positions: Dictionary = _definitions["positions"]
			var bases: Dictionary = {"A": "PANEL_WEST", "B": "PANEL_SPUR", "C": "R_WEST"}
			for letter: String in ["A", "B", "C"]:
				var offset_cm: Array = exp013_case["station_offsets_cm"][letter]
				var offset_m: Vector3 = Vector3(
					float(offset_cm[0]) / 100.0, 0.0, float(offset_cm[1]) / 100.0)
				exp013_positions[str(exp013_case["targets"][letter])] = \
					exp013_positions[str(bases[letter])] + offset_m
			# The source-defined markers do NOT certify physical accessibility.
	# EXP014 A02: additive post-intervention state only; all existing site
	# definitions/positions and the original 1,000 task bindings stay immutable.
	if enable_site_contingency:
		var originals: Array[Dictionary] = []
		for prior: Dictionary in SiteA02.load_book().get("entries", []):
			originals.append(prior)
		for source_book: Dictionary in SiteEXP013.load_available_books():
			for prior: Dictionary in source_book["entries"]:
				originals.append(prior)
		var contingency_book: Dictionary = SiteContingencies.load_book()
		var contingency_audit: Dictionary = SiteContingencies.inspect(
			atlas, originals, contingency_book)
		if not bool(contingency_audit.get("ok", false)):
			return _fail("EXP014_CONTINGENCY_BOOK_INVALID", contingency_audit)
		var contingency_case: Dictionary = SiteContingencies.entry_for(
			contingency_book, level_id)
		if contingency_case.is_empty() or (site_a02 == null and site_exp013 == null):
			return _fail("EXP014_SITE_SOURCE_NOT_AVAILABLE")
		site_contingency = SiteContingencies.new()
		var contingency_configured: Dictionary = site_contingency.configure(contingency_case)
		if not bool(contingency_configured.get("ok", false)):
			return _fail("EXP014_CONTINGENCY_CONFIG_INVALID", contingency_configured)
		_definitions["site_contingency"] = site_contingency.definition_snapshot()
	# EXP014 A05 is a new opt-in pre-intervention host state machine. The
	# source case and targets are inherited, not supplied by a client command.
	if enable_site_approach:
		var original_site: SiteA02 = site_exp013 if site_exp013 != null else site_a02
		if original_site == null:
			return _fail("EXP014_A05_ORIGINAL_SITE_MISSING")
		site_approach = SiteApproach.new()
		var approach_gate: Dictionary = site_approach.configure(plan, original_site.definition_snapshot())
		if not bool(approach_gate.get("ok", false)):
			return _fail("EXP014_A05_SOURCE_INVALID", approach_gate)
		_definitions["site_approach"] = site_approach.definition_snapshot()
	# A06 is fully opt-in, bound to both immutable predecessor definitions.
	if enable_site_outcomes:
		site_outcomes = SiteOutcomes.new()
		var outcome_gate: Dictionary = site_outcomes.configure(
			site_approach.definition_snapshot(), site_contingency.definition_snapshot())
		if not bool(outcome_gate.get("ok", false)):
			return _fail("EXP014_A06_SOURCE_INVALID", outcome_gate)
		_definitions["site_outcomes"] = site_outcomes.definition_snapshot()
	# A07 binds to the original host source pair plus A06; no new targets.
	if enable_site_hazards:
		site_hazards = SiteHazards.new()
		var hazard_gate: Dictionary = site_hazards.configure(
			site_approach.definition_snapshot(), site_outcomes.definition_snapshot(),
			site_contingency.definition_snapshot())
		if not bool(hazard_gate.get("ok", false)):
			return _fail("EXP014_A07_SOURCE_INVALID", hazard_gate)
		_definitions["site_hazards"] = site_hazards.definition_snapshot()
	# Explicit per-case evidence graphs retain existing SC target authority.
	if enable_site_puzzles:
		var puzzle_book: Dictionary = SitePuzzles.load_book()
		var case_source: Dictionary = site_contingency.definition_snapshot()
		var puzzle_entry: Dictionary = SitePuzzles.entry_for(puzzle_book, level_id)
		site_puzzles = SitePuzzles.new()
		var puzzle_gate: Dictionary = site_puzzles.configure(
			case_source, puzzle_entry, site_hazards.definition_snapshot())
		if not bool(puzzle_gate.get("ok", false)):
			return _fail("EXP014_A08_SOURCE_INVALID", puzzle_gate)
		_definitions["site_puzzles"] = site_puzzles.definition_snapshot()
	# EXP016 cases are opt-in and source-pinned to the original A08 evidence graph.
	if enable_advanced_cases:
		var advanced_books: Array[Dictionary] = AdvancedCases.load_available_books()
		var selected_case: Dictionary = {}
		for advanced_book: Dictionary in advanced_books:
			var case_audit: Dictionary = AdvancedCases.inspect(atlas, SitePuzzles.load_book(), advanced_book)
			if not bool(case_audit.get("ok", false)):
				return _fail("EXP016_SOURCE_INVALID", case_audit)
			var candidate: Dictionary = AdvancedCases.entry_for(advanced_book, level_id)
			if not candidate.is_empty():
				if not selected_case.is_empty():
					return _fail("EXP016_OVERLAPPING_CASEBOOKS")
				selected_case = candidate
		if selected_case.is_empty():
			return _fail("EXP016_CASE_NOT_AUTHORED")
		_definitions["advanced_case_phase"] = "A%02d" % (int((int(level_id.trim_prefix("LV_")) - 1) / 50.0) + 2)
		advanced_cases = AdvancedCases.new()
		var case_config: Dictionary = advanced_cases.configure(selected_case)
		if not bool(case_config.get("ok", false)):
			return _fail("EXP016_A02_CONFIG_FAILED", case_config)
		if enable_advanced_fault_layers:
			var fault_layer_book: Dictionary = AdvancedFaults.load_book()
			var faults_audit: Dictionary = AdvancedFaults.inspect(
				atlas, Faults.load_book(), Bespoke.load_book(), fault_layer_book)
			if not bool(faults_audit.get("ok", false)):
				return _fail("EXP016_A06_FAULT_SOURCE_INVALID", faults_audit)
			var layer: Dictionary = AdvancedFaults.entry_for(fault_layer_book, level_id)
			var bound: Dictionary = advanced_cases.bind_fault_layer(layer)
			if not bool(bound.get("ok", false)):
				return _fail("EXP016_A06_FAULT_LAYER_BINDING_FAILED", bound)
		if enable_advanced_environment:
			var hazard_book: Dictionary = AdvancedHazards.load_book()
			var hazard_audit: Dictionary = AdvancedHazards.inspect(atlas,
				Bespoke.load_book(), SiteContingencies.load_book(), hazard_book)
			if not bool(hazard_audit.get("ok", false)):
				return _fail("EXP016_A07_HAZARD_SOURCE_INVALID", hazard_audit)
			var hazard_protocol: Dictionary = AdvancedHazards.entry_for(hazard_book, level_id)
			var hazard_binding: Dictionary = advanced_cases.bind_hazard_protocol(hazard_protocol)
			if not bool(hazard_binding.get("ok", false)):
				return _fail("EXP016_A07_HAZARD_BIND_FAILED", hazard_binding)
		if enable_advanced_equipment:
			var equipment_book: Dictionary = AdvancedEquipment.load_book()
			var equipment_audit: Dictionary = AdvancedEquipment.inspect(
				atlas, Worksite.load_book(), equipment_book)
			if not bool(equipment_audit.get("ok", false)):
				return _fail("EXP016_A08_EQUIPMENT_SOURCE_INVALID", equipment_audit)
			var gear: Dictionary = AdvancedEquipment.entry_for(equipment_book, level_id)
			var accepted_gear: Dictionary = advanced_cases.bind_equipment_manifest(gear)
			if not bool(accepted_gear.get("ok", false)):
				return _fail("EXP016_A08_EQUIPMENT_BIND_FAILED", accepted_gear)
		if enable_advanced_policy:
			var policy_book: Dictionary = AdvancedPolicies.load_book()
			var policy_audit: Dictionary = AdvancedPolicies.inspect(
				atlas, SiteContingencies.load_book(), policy_book)
			if not bool(policy_audit.get("ok", false)):
				return _fail("EXP016_A09_POLICY_SOURCE_INVALID", policy_audit)
			var policy_spec: Dictionary = AdvancedPolicies.entry_for(policy_book, level_id)
			var policy_bound: Dictionary = advanced_cases.bind_source_policy(policy_spec)
			if not bool(policy_bound.get("ok", false)):
				return _fail("EXP016_A09_POLICY_BIND_FAILED", policy_bound)
		if enable_advanced_cascade:
			var cascade_book: Dictionary = AdvancedCascade.load_book()
			var cascade_audit: Dictionary = AdvancedCascade.inspect(
				atlas, RegionalNetworks.load_book(), cascade_book)
			if not bool(cascade_audit.get("ok", false)):
				return _fail("EXP016_A10_CASCADE_SOURCE_INVALID", cascade_audit)
			var regional_source: Dictionary = AdvancedCascade.entry_for(cascade_book, level_id)
			advanced_cascade = AdvancedCascade.new()
			var inherited: Dictionary = advanced_cascade.configure(
				regional_source, account_key, level_id)
			if not bool(inherited.get("ok", false)):
				return _fail("EXP016_A10_CASCADE_SCOPE_INVALID", inherited)
			var carry: Dictionary = advanced_cases.bind_inherited_pressure(
				int(inherited["inherited_pressure"]))
			if not bool(carry.get("ok",false)):
				return _fail("EXP016_A10_CASCADE_BIND_FAILED", carry)
		if enable_advanced_discoveries:
			var discovery_book: Dictionary = AdvancedDiscoveries.load_book()
			var discovery_audit: Dictionary = AdvancedDiscoveries.inspect(
				atlas, SitePuzzles.load_book(), discovery_book)
			if not bool(discovery_audit.get("ok", false)):
				return _fail("EXP016_A11_DISCOVERY_SOURCE_INVALID", discovery_audit)
			var source_find: Dictionary = AdvancedDiscoveries.entry_for(
				discovery_book, level_id)
			var attached: Dictionary = advanced_cases.bind_source_discovery(source_find)
			if not bool(attached.get("ok", false)):
				return _fail("EXP016_A11_DISCOVERY_BIND_FAILED", attached)
		_definitions["advanced_cases"] = advanced_cases.definition_snapshot()
	_position_source = host_position
	_physics_visibility = physics_visibility
	_account_key = account_key
	# Lore ownership never participates in the grid, equipment, or repair state.
	_collectible = level["collectible"].duplicate(true)
	var item_id: String = str(_collectible["id"])
	(_definitions["positions"] as Dictionary)[item_id] = 		(_definitions["positions"] as Dictionary)["PANEL_SPUR"] + Vector3(0.0, -0.35, 0.55)
	grid = Grid.new()
	meter = Meter.new()
	interaction = Interaction.new()
	equipment = Equipment.new()
	mission = Mission.new()
	var errors: Array[Dictionary] = []
	errors.append_array(grid.load_definition(_definitions["grid"]))
	if not errors.is_empty():
		return _fail("GRID_INVALID", errors)
	errors.append_array(meter.load_definition(_definitions["meter"], grid))
	errors.append_array(interaction.load_definition(
		_json("res://content/interaction.json"), _definitions["repairs"], grid, meter))
	errors.append_array(equipment.load_definition(_definitions["equipment"], grid, meter))
	if not errors.is_empty():
		return _fail("SERVICE_INVALID", errors)
	errors.append_array(mission.load_definition(_definitions["mission"], grid, interaction, equipment))
	if not errors.is_empty():
		return _fail("MISSION_INVALID", errors)
	host = Host.new()
	var rev: String = _content_revision()
	var sid: String = _session_id()
	errors.append_array(host.configure(_json("res://content/network.json"), PROTOCOL,
		rev, sid, grid, meter, interaction, equipment,
		_definitions["switches"], Callable(self, "_in_range")))
	if not errors.is_empty():
		return _fail("HOST_INVALID", errors)
	host.set_position_provider(Callable(self, "_position_cm"))
	host.set_mission(mission)
	host.set_collectible_authority(Callable(self, "_claim_lore"), Callable(self, "_lore_state"))
	if bespoke != null:
		host.set_expedition_intent_guard(Callable(self, "_bespoke_guard"))
	if devices != null:
		host.set_expedition_device_authority(Callable(self, "_operate_device"),
			Callable(devices, "snapshot"))
	if faults != null:
		host.set_expedition_fault_authority(Callable(self, "_operate_fault"),
			Callable(faults, "snapshot"), Callable(self, "_fault_tick"))
	if consequences != null:
		host.set_expedition_consequence_authority(Callable(self, "_operate_consequence"),
			Callable(consequences, "snapshot"), Callable(self, "_consequence_tick"))
	if logistics != null:
		host.set_expedition_logistics_authority(Callable(self, "_operate_logistics"),
			Callable(logistics, "snapshot"), Callable(self, "_logistics_tick"))
	if balancing != null:
		host.set_expedition_balance_authority(Callable(self, "_operate_balance"),
			Callable(balancing, "snapshot"), Callable(self, "_balance_tick"))
	if worksite != null:
		host.set_expedition_worksite_authority(Callable(self, "_operate_worksite"),
			Callable(self, "_worksite_snapshot"), Callable(self, "_worksite_tick"))
	var accepted: Dictionary = host.admit(Host.HOST_PEER, PLAYER_ID, PROTOCOL, rev, TOOLS)
	if not bool(accepted.get("ok", false)):
		return _fail("ADMISSION_REFUSED", accepted)
	var begun: Dictionary = host.begin_after_briefing()
	if not bool(begun.get("ok", false)):
		return _fail("BRIEFING_REFUSED", begun)
	_tasks.clear()
	for task: Dictionary in level["tasks"]:
		_tasks.append({"id": str(task["id"]), "kind": str(task["kind"]),
			"title": str(task["title"]), "required": bool(task["required"])})
	_ready = true
	return {"ok": true, "level_id": level_id, "session": sid, "content_revision": rev,
		"task_count": _tasks.size(), "bespoke_active": bespoke != null,
		"devices_active": devices != null, "faults_active": faults != null,
		"consequences_active": consequences != null,
		"logistics_active": logistics != null, "balance_active": balancing != null,
		"worksite_active": worksite != null, "site_a02_active": site_a02 != null,
		"site_exp013_active": site_exp013 != null, "site_contingency_active": site_contingency != null,
		"site_approach_active": site_approach != null,
		"site_outcomes_active": site_outcomes != null,
		"site_hazards_active": site_hazards != null,
		"site_puzzles_active": site_puzzles != null,
		"regional_network_active": regional_network != null,
		"qualification": "AUTHORITY_SOURCE_HEADLESS_ONLY_NO_PLAYABILITY"}


## EXP016 A12 internal source/headless qualifier. Not a player-launch path:
## opt-in full EXP016 source stack excluding authenticated regional campaigns.
## No new RPC, production save, credits, or release/certification promise.
func start_exp016_source_qualification(level_id: String,
		host_position: Callable) -> Dictionary:
	return start(level_id, host_position, Callable(), "", false, "",
		true,  # enable_bespoke
		true,  # enable_devices
		true,  # enable_faults
		true,  # enable_consequences
		true,  # enable_logistics
		true,  # enable_balance
		true,  # enable_worksite
		true,  # enable_site_a02
		true,  # enable_site_exp013
		true,  # enable_site_contingency
		true,  # enable_site_approach
		true,  # enable_site_outcomes
		true,  # enable_site_hazards
		true,  # enable_site_puzzles
		false,  # enable_regional_networks
		true,  # enable_advanced_cases
		true,  # enable_advanced_fault_layers
		true,  # enable_advanced_environment
		true,  # enable_advanced_equipment
		true,  # enable_advanced_policy
		false,  # enable_advanced_cascade
		true  # enable_advanced_discoveries)


func _session_id() -> String:
	return "S_EXP03_" + str(_definitions.get("level_id", "UNKNOWN"))


func _content_revision() -> String:
	if advanced_cases != null:
		return "EXP016_" + str(_definitions.get("advanced_case_phase", "A02")) + "_" + ("%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			JSON.stringify(advanced_cases.definition_snapshot())]).sha256_text()
	if regional_network != null:
		return "EXP014_A09_" + ("%s|%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			JSON.stringify(site_puzzles.definition_snapshot()),
			JSON.stringify(RegionalNetworks.entry_for(
				RegionalNetworks.load_book(), str(_definitions.get("level_id", ""))))]).sha256_text()
	if site_puzzles != null:
		return "EXP014_A08_" + ("%s|%s|%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			JSON.stringify(site_approach.definition_snapshot()),
			JSON.stringify(site_hazards.definition_snapshot()),
			JSON.stringify(site_puzzles.definition_snapshot())]).sha256_text()
	if site_hazards != null:
		return "EXP014_A07_" + ("%s|%s|%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			JSON.stringify(site_approach.definition_snapshot()),
			JSON.stringify(site_outcomes.definition_snapshot()),
			JSON.stringify(site_hazards.definition_snapshot())]).sha256_text()
	if site_outcomes != null:
		return "EXP014_A06_" + ("%s|%s|%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			JSON.stringify(site_approach.definition_snapshot()),
			JSON.stringify(site_contingency.definition_snapshot()),
			JSON.stringify(site_outcomes.definition_snapshot())]).sha256_text()
	if site_approach != null:
		return "EXP014_A05_" + ("%s|%s|%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			JSON.stringify(site_approach.definition_snapshot()),
			JSON.stringify(site_contingency.definition_snapshot()),
			JSON.stringify((site_exp013 if site_exp013 != null else site_a02).definition_snapshot())]).sha256_text()
	if site_contingency != null:
		var original: SiteA02 = site_exp013 if site_exp013 != null else site_a02
		return "EXP014_" + ("%s|%s|%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			str(worksite.definition_snapshot().get("encounter_key", "")),
			JSON.stringify(original.definition_snapshot()),
			JSON.stringify(site_contingency.definition_snapshot())]).sha256_text()
	if site_exp013 != null:
		return "EXP013_" + ("%s|%s|%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			str(balancing.definition_snapshot().get("load_key", "")),
			str(worksite.definition_snapshot().get("encounter_key", "")),
			JSON.stringify(site_exp013.definition_snapshot())]).sha256_text()
	if site_a02 != null:
		return "EXP012A02_" + ("%s|%s|%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			str(balancing.definition_snapshot().get("load_key", "")),
			str(worksite.definition_snapshot().get("encounter_key", "")),
			JSON.stringify(site_a02.definition_snapshot())]).sha256_text()
	if worksite != null:
		return "EXP012_" + ("%s|%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			str(balancing.definition_snapshot().get("load_key", "")),
			str(worksite.definition_snapshot().get("encounter_key", ""))]).sha256_text()
	if balancing != null:
		return "EXP011_" + ("%s|%s|%s|%s|%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			str(devices.definition_snapshot().get("graph_key", "")),
			str(faults.definition_snapshot().get("scenario_key", "")),
			str(consequences.definition_snapshot().get("chain_key", "")),
			str(logistics.definition_snapshot().get("logistics_key", "")),
			str(balancing.definition_snapshot().get("load_key", ""))]).sha256_text()
	if logistics != null:
		return "EXP010_" + ("%s|%s|%s|%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			str(devices.definition_snapshot().get("graph_key", "")),
			str(faults.definition_snapshot().get("scenario_key", "")),
			str(consequences.definition_snapshot().get("chain_key", "")),
			str(logistics.definition_snapshot().get("logistics_key", ""))]).sha256_text()
	if consequences != null:
		return "EXP009_" + ("%s|%s|%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			str(devices.definition_snapshot().get("graph_key", "")),
			str(faults.definition_snapshot().get("scenario_key", "")),
			str(consequences.definition_snapshot().get("chain_key", ""))]).sha256_text()
	if faults != null:
		return "EXP08_" + ("%s|%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			str(devices.definition_snapshot().get("graph_key", "")),
			str(faults.definition_snapshot().get("scenario_key", ""))]).sha256_text()
	if devices != null:
		return "EXP07_" + ("%s|%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			str(bespoke.definition_snapshot().get("encounter_key", "")),
			str(devices.definition_snapshot().get("graph_key", ""))]).sha256_text()
	if bespoke != null:
		return "EXP06_" + ("%s|%s" % [
			str(_definitions.get("source_fingerprint", "")),
			str(bespoke.definition_snapshot().get("encounter_key", ""))]).sha256_text()
	return "EXP03_" + str(_definitions.get("source_fingerprint", ""))


func session_id() -> String:
	return _session_id() if _ready else ""


func definition_snapshot() -> Dictionary:
	return _definitions.duplicate(true)


## Real SessionHost receives the exact client message and checks peer identity,
## session ID, sequence, rate, permissions, tools and range. No direct grid.apply
## or direct repair mutation is exposed here.
func receive(peer_id: int, message: PackedByteArray) -> Dictionary:
	if not _ready:
		return _fail("SESSION_NOT_READY")
	var reply: Dictionary = host.receive(peer_id, message)
	if not bool(reply.get("ok", false)) or bool(reply.get("duplicate", false)):
		return reply
	# Decode only AFTER the host accepted the envelope. A decoded task ID or
	# player-supplied success flag is neither requested nor consumed.
	var command: Variant = JSON.parse_string(message.get_string_from_utf8())
	if command is Dictionary:
		var action: Dictionary = command
		if action.get("type") == "inspect" and \
				["PANEL_WEST", "PANEL_SPUR"].has(str(action.get("entity", ""))):
			var panel: String = str(action["entity"])
			var snapshots: Dictionary = meter.canonical_state()["snapshots"]
			if snapshots.has(panel):
				_observed_inspections[panel] = true
	if bespoke != null and command is Dictionary:
		bespoke.accepted(str(command.get("type", "")),
			str(command.get("entity", "")), command.get("payload", {}),
			grid.canonical_state(), interaction.canonical_state()["repairs"])
	_update_progress()
	return reply


## Only SessionHost may invoke this after shape, member, sequence and dedupe checks.
func _bespoke_guard(player_id: String, kind: String, entity: String,
		_payload: Dictionary) -> Dictionary:
	if player_id != PLAYER_ID or bespoke == null:
		return _fail("EXP06_INVALID_HOST_PRINCIPAL")
	# Opt-in A09 extraction MUST be independently gated by a host-owned
	# regional decision. Never trust a client-supplied preparation boolean.
	if kind == "request_extract" and regional_network != null \
			and not regional_network.site_prepared():
		return _fail("EXP014_A09_PREPARATION_REQUIRED")
	if kind == "request_extract" and devices != null and not devices.solved():
		return _fail("EXP07_DEVICES_INCOMPLETE")
	if kind == "request_extract" and faults != null and not faults.solved():
		return _fail("EXP08_FAULTS_INCOMPLETE")
	if kind == "request_extract" and consequences != null and not consequences.solved():
		return _fail("EXP009_CONSEQUENCES_INCOMPLETE")
	if kind == "request_extract" and logistics != null and not logistics.solved():
		return _fail("EXP010_LOGISTICS_INCOMPLETE")
	if kind == "request_extract" and balancing != null and not balancing.solved():
		return _fail("EXP011_BALANCING_INCOMPLETE")
	if kind == "request_extract" and worksite != null and not worksite.solved():
		return _fail("EXP012_WORKSITE_INCOMPLETE")
	if kind == "request_extract" and site_a02 != null and not site_a02.solved():
		return _fail("EXP012A02_SITE_INCOMPLETE")
	if kind == "request_extract" and site_exp013 != null and not site_exp013.solved():
		return _fail("EXP013_SITE_INCOMPLETE")
	if kind == "request_extract" and site_contingency != null and not site_contingency.solved():
		return _fail("EXP014_CONTINGENCY_INCOMPLETE")
	if kind == "request_extract" and site_approach != null and not site_approach.solved():
		return _fail("EXP014_A05_INTELLIGENCE_INCOMPLETE")
	if kind == "request_extract" and site_outcomes != null and not site_outcomes.solved():
		return _fail("EXP014_A06_OUTCOMES_INCOMPLETE")
	if kind == "request_extract" and site_hazards != null and not site_hazards.solved():
		return _fail("EXP014_A07_ENVIRONMENT_UNVERIFIED")
	if kind == "request_extract" and site_puzzles != null and not site_puzzles.solved():
		return _fail("EXP014_A08_INVESTIGATION_INCOMPLETE")
	if kind == "operate_worksite" and (worksite == null or \
			(not worksite.target_ids().has(entity) and \
			(site_a02 == null or not site_a02.target_ids().has(entity)) and \
			(site_exp013 == null or not site_exp013.target_ids().has(entity)))):
		return _fail("EXP012_UNKNOWN_TARGET")
	if kind == "operate_balance":
		if balancing == null or not balancing.target_ids().has(entity):
			return _fail("EXP011_UNKNOWN_TARGET")
	if kind == "operate_logistics":
		if logistics == null or not logistics.target_ids().has(entity):
			return _fail("EXP010_UNKNOWN_TARGET")
	if kind == "operate_consequence":
		if consequences == null or not consequences.target_ids().has(entity):
			return _fail("EXP009_UNKNOWN_TARGET")
	if kind == "operate_fault":
		if faults == null or not faults.target_ids().has(entity):
			return _fail("EXP08_UNKNOWN_TARGET")
		if devices == null or not devices.solved():
			return _fail("EXP08_DEVICES_REQUIRED")
	if kind == "operate_device":
		if devices == null or devices.device_definition(entity).is_empty():
			return _fail("EXP07_UNKNOWN_DEVICE")
		if bool(devices.device_definition(entity).get("hazard_sensitive", false)) and \
				bespoke.hazard_active():
			return _fail("EXP07_HAZARD_LOCKOUT")
	return bespoke.preflight(kind, entity)


## Device progress mutates exclusively after SessionHost validates the peer,
## sequence, dedupe, source entity and host-owned physical range / sight.
func _operate_device(player_id: String, entity: String, action: String) -> Dictionary:
	if player_id != PLAYER_ID or devices == null:
		return _fail("EXP07_DEVICE_AUTHORITY_MISSING")
	var edges: Dictionary = grid.canonical_state()["edges"]
	var repairs: Dictionary = interaction.canonical_state()["repairs"]
	var facts: Dictionary = {
		"west_inspected": _observed_inspections.has("PANEL_WEST"),
		"east_on": bool(edges["E_GRID_EAST"]["enabled"]),
		"west_restored": str(repairs["R_WEST"]["state"]) == "restored"
	}
	return devices.operate(entity, action, facts)



## EXP08: facts are reconstructed solely from live host services, never from wire bytes.
func _fault_facts() -> Dictionary:
	var edges: Dictionary = grid.canonical_state()["edges"]
	var repairs: Dictionary = interaction.canonical_state()["repairs"]
	return {
		"west_inspected": _observed_inspections.has("PANEL_WEST"),
		"east_on": bool(edges["E_GRID_EAST"]["enabled"]),
		"spur_on": bool(edges["E_GRID_SPUR"]["enabled"]),
		"west_restored": str(repairs["R_WEST"]["state"]) == "restored",
		"devices_solved": devices != null and devices.solved(),
		"hazard_active": bespoke != null and bespoke.hazard_active()
	}


func _operate_fault(player_id: String, entity: String, action: String) -> Dictionary:
	if player_id != PLAYER_ID or faults == null:
		return _fail("EXP08_HOST_PRINCIPAL_INVALID")
	return faults.operate(entity, action, _fault_facts())


func _fault_tick() -> void:
	if faults != null:
		faults.advance(_fault_facts())


func _consequence_facts() -> Dictionary:
	var facts: Dictionary = _fault_facts()
	facts["fault_phase"] = str(faults.snapshot().get("phase", "")) if faults != null else ""
	facts["faults_solved"] = faults != null and faults.solved()
	return facts


func _operate_consequence(player_id: String, entity: String, action: String) -> Dictionary:
	if player_id != PLAYER_ID or consequences == null:
		return _fail("EXP009_HOST_PRINCIPAL_INVALID")
	return consequences.operate(entity, action, _consequence_facts())


func _consequence_tick() -> void:
	if consequences != null:
		consequences.advance(_consequence_facts())


## EXP010 reads only live host facts; none are accepted from network payload.
func _logistics_facts() -> Dictionary:
	var facts: Dictionary = _consequence_facts()
	facts["consequences_solved"] = consequences != null and consequences.solved()
	return facts


func _operate_logistics(player_id: String, entity: String, action: String) -> Dictionary:
	if player_id != PLAYER_ID or logistics == null:
		return _fail("EXP010_HOST_PRINCIPAL_INVALID")
	return logistics.operate(entity, action, _logistics_facts())


func _logistics_tick() -> void:
	if logistics != null:
		logistics.advance(_logistics_facts())


## EXP011 derives downstream safety from the same current host services.
func _balance_facts() -> Dictionary:
	var facts: Dictionary = _logistics_facts()
	facts["logistics_solved"] = logistics != null and logistics.solved()
	return facts


func _operate_balance(player_id: String, entity: String, action: String) -> Dictionary:
	if player_id != PLAYER_ID or balancing == null:
		return _fail("EXP011_HOST_PRINCIPAL_INVALID")
	return balancing.operate(entity, action, _balance_facts())


func _balance_tick() -> void:
	if balancing != null:
		balancing.advance(_balance_facts())


## The five source task IDs are read-only host evidence. The fifth restoration
## task remains extraction-dependent; requiring it now would deadlock extraction.
func _worksite_facts() -> Dictionary:
	var facts: Dictionary = _balance_facts()
	facts["balancing_solved"] = balancing != null and balancing.solved()
	facts["investigation_solved"] = _completed.has(str(_tasks[0]["id"]))
	facts["routing_solved"] = _completed.has(str(_tasks[1]["id"]))
	facts["repair_solved"] = _completed.has(str(_tasks[2]["id"]))
	facts["discovery_solved"] = _completed.has(str(_tasks[3]["id"]))
	if worksite != null:
		var order_state: Dictionary = worksite.snapshot()
		facts["worksite_opened"] = bool(order_state["opened"])
		facts["worksite_route"] = str(order_state["route"])
	return facts


func _contingency_facts() -> Dictionary:
	var facts: Dictionary = _worksite_facts()
	var original: SiteA02 = site_exp013 if site_exp013 != null else site_a02
	facts["site_intervention_solved"] = original != null and original.solved()
	return facts


func _outcome_facts() -> Dictionary:
	var facts: Dictionary = _contingency_facts()
	facts["site_contingency_solved"] = site_contingency != null and site_contingency.solved()
	return facts


func _hazard_facts() -> Dictionary:
	var facts: Dictionary = _outcome_facts()
	facts["outcome_mode"] = str(site_outcomes.snapshot().get("mode", "")) if site_outcomes != null else ""
	return facts


# Original tool admission is host-owned; never sourced from client command.
func _puzzle_facts() -> Dictionary:
	var facts: Dictionary = _hazard_facts()
	if advanced_cases != null:
		# Source-owned upstream worksite guard, not an arbitrary client boolean.
		facts["load_balanced"] = balancing != null and balancing.solved()
		facts["supplies_ready"] = logistics != null and logistics.solved()
		facts["cascade_stable"] = consequences != null and consequences.solved()
		facts["fault_clear"] = faults != null and faults.solved()
	if advanced_cases != null:
		facts["authorized_tools"] = TOOLS.duplicate()
	facts["hazard_safe"] = site_hazards != null and site_hazards.can_operate()
	facts["recon_route"] = site_approach.selected_route() if site_approach != null else ""
	return facts


func _operate_worksite(player_id: String, entity: String, action: String) -> Dictionary:
	if player_id != PLAYER_ID or worksite == null:
		return _fail("EXP012_HOST_PRINCIPAL_INVALID")
	# These requests enter only through the existing SessionHost worksite intent,
	# after its principal, sequence, dedupe, range and rate validation. The
	# original board target is reused; there is no new network action RPC.
	if regional_network != null and entity == str(worksite.definition_snapshot()["board"]):
		match action:
			"regional_critical":
				return regional_network.select_strategy("critical_first")
			"regional_resilience":
				return regional_network.select_strategy("resilience_first")
			"regional_buffer":
				return regional_network.prepare_site("buffer")
			"regional_managed":
				return regional_network.prepare_site("managed")
			"regional_recharge":
				return regional_network.host_transition("recharge_reserve",
					str(regional_network.snapshot()["reserve_anchor"]))
		if action.begins_with("regional_isolate:"):
			return regional_network.host_transition("isolate_feeder",
				action.get_slice(":", 1))
		if action.begins_with("regional_reset:"):
			return regional_network.host_transition("reset_feeder",
				action.get_slice(":", 1))
		if action.begins_with("regional_engage:"):
			return regional_network.host_transition("engage_tie",
				action.get_slice(":", 1))
		if action.begins_with("regional_release:"):
			return regional_network.host_transition("release_tie",
				action.get_slice(":", 1))
	var active: SiteA02 = site_exp013 if site_exp013 != null else site_a02
	if active != null and active.target_ids().has(entity):
		if site_approach != null and not site_approach.solved():
			var recon_reply: Dictionary = site_approach.operate(entity, action, _worksite_facts())
			if bool(recon_reply.get("ok", false)) and site_approach.solved() and site_outcomes != null:
				site_outcomes.begin(site_approach.snapshot())
			return recon_reply
		if site_outcomes != null and not site_outcomes.prepared():
			var plan_reply: Dictionary = site_outcomes.operate(entity, action, _outcome_facts())
			if bool(plan_reply.get("ok", false)) and site_outcomes.prepared() and site_hazards != null:
				site_hazards.begin(site_outcomes.snapshot())
			return plan_reply
		if site_hazards != null and site_hazards.needs_action():
			return site_hazards.operate(entity, action, _hazard_facts())
		if site_puzzles != null and site_puzzles.needs_action():
			return site_puzzles.operate(entity, action, _puzzle_facts())
		if advanced_cases != null and site_puzzles != null and site_puzzles.solved():
			if not advanced_cases.started():
				advanced_cases.begin()
			if advanced_cases.needs_action() or action.begins_with("case_discover_"):
				var case_reply: Dictionary = advanced_cases.operate(
					entity, action, _puzzle_facts())
				if bool(case_reply.get("ok",false)) and advanced_cases.solved() and \
						advanced_cascade != null:
					var carry_reply: Dictionary = advanced_cascade.record_host_completion(
						advanced_cases.snapshot())
					if not bool(carry_reply.get("ok", false)):
						return _fail("EXP016_A10_CASCADE_WRITE_HOLD", carry_reply)
				return case_reply
		if site_outcomes != null and site_outcomes.needs_action():
			return site_outcomes.operate(entity, action, _outcome_facts())
		if site_contingency != null and active.solved():
			return site_contingency.operate(entity, action, _contingency_facts())
		return active.operate(entity, action, _worksite_facts())
	if regional_network != null and entity == str(worksite.definition_snapshot()["decision"]) \
			and ["priority", "resilience"].has(action) and not regional_network.site_prepared():
		return _fail("EXP014_A09_REGIONAL_PREPARATION_REQUIRED")
	# A07 exposure/fault can block unsafe worksite operations and routing,
	# but does not prevent opening the original source review board.
	if site_hazards != null and worksite.target_ids().has(entity) and \
			entity != str(worksite.definition_snapshot()["board"]) and \
			not site_hazards.can_operate():
		return _fail("EXP014_A07_HAZARD_LOCKED")
	if advanced_cases != null and worksite.target_ids().has(entity) and \
			entity != str(worksite.definition_snapshot()["board"]) and \
			not advanced_cases.solved():
		return _fail("EXP016_A02_CASEWORK_REQUIRED")
	# Existing work order cannot bypass a newly required investigation graph.
	if site_puzzles != null and worksite.target_ids().has(entity) and \
			entity != str(worksite.definition_snapshot()["board"]) and \
			not site_puzzles.solved():
		return _fail("EXP014_A08_INVESTIGATION_REQUIRED")
	# The A01 choice and one authored site overlay must agree atomically.
	# An attempted reroute after intervention begins cannot fork host states.
	if active != null and entity == str(worksite.definition_snapshot()["decision"]) and \
			["priority", "resilience"].has(action) and site_outcomes != null and \
			not site_outcomes.prepared():
		return _fail("EXP014_A06_CONSEQUENCE_PLAN_REQUIRED")
	if active != null and entity == str(worksite.definition_snapshot()["decision"]) and \
			["priority", "resilience"].has(action) and site_approach != null and \
			(not site_approach.solved() or site_approach.selected_route() != action):
		return _fail("EXP014_A05_RECON_OR_ROUTE_UNVERIFIED")
	if active != null and entity == str(worksite.definition_snapshot()["decision"]) and \
			["priority", "resilience"].has(action) and \
			(not active.can_choose_route(action) or \
			(site_contingency != null and not site_contingency.can_choose_route(action))):
		return _fail("EXP014_ROUTE_LOCKED" if site_contingency != null else \
			"EXP013_ROUTE_LOCKED" if site_exp013 != null else "EXP012A02_ROUTE_LOCKED")
	var reply: Dictionary = worksite.operate(entity, action, _worksite_facts())
	if bool(reply.get("ok", false)) and active != null and \
			entity == str(worksite.definition_snapshot()["decision"]):
		var binding: Dictionary = active.choose_route(action)
		if not bool(binding.get("ok", false)):
			return _fail("EXP013_ROUTE_SYNC_FAILED" if site_exp013 != null else "EXP012A02_ROUTE_SYNC_FAILED")
		if site_contingency != null:
			var synced: Dictionary = site_contingency.choose_route(action)
			if not bool(synced.get("ok", false)):
				return _fail("EXP014_ROUTE_SYNC_FAILED")
	return reply


func _worksite_tick() -> void:
	if worksite != null:
		worksite.advance(_worksite_facts())
	if site_a02 != null:
		site_a02.advance(_worksite_facts())
	if site_exp013 != null:
		site_exp013.advance(_worksite_facts())
	if site_contingency != null:
		site_contingency.advance(_contingency_facts())
	if site_approach != null:
		site_approach.advance(_worksite_facts())
	if site_outcomes != null:
		if not site_outcomes.started() and site_approach.solved():
			site_outcomes.begin(site_approach.snapshot())
		site_outcomes.advance(_outcome_facts())
	if site_hazards != null:
		if not site_hazards.started() and site_outcomes.prepared():
			site_hazards.begin(site_outcomes.snapshot())
		site_hazards.advance(_hazard_facts())
	if advanced_cases != null and site_puzzles != null and site_puzzles.solved() and \
			not advanced_cases.started():
		advanced_cases.begin()
	if site_puzzles != null:
		if not site_puzzles.started() and str(site_hazards.snapshot().get("phase", "")) == "contained":
			site_puzzles.begin(site_hazards.snapshot())
		site_puzzles.advance(_puzzle_facts())


func _worksite_snapshot() -> Dictionary:
	if worksite == null:
		return {}
	var state: Dictionary = worksite.snapshot()
	if site_a02 != null:
		state["site_a02"] = site_a02.snapshot()
	if site_exp013 != null:
		state["site_exp013"] = site_exp013.snapshot()
	if site_contingency != null:
		state["site_contingency"] = site_contingency.snapshot()
	if site_approach != null:
		state["site_approach"] = site_approach.snapshot()
	if site_outcomes != null:
		state["site_outcomes"] = site_outcomes.snapshot()
	if site_hazards != null:
		state["site_hazards"] = site_hazards.snapshot()
	if site_puzzles != null:
		state["site_puzzles"] = site_puzzles.snapshot()
	if advanced_cascade != null:
		state["advanced_cascade"] = advanced_cascade.snapshot()
	if advanced_cases != null:
		state["advanced_cases"] = advanced_cases.snapshot()
	if regional_network != null:
		state["regional_network"] = regional_network.snapshot()
	return state


## Called by SessionHost ONLY after its existing transport/session/sequence,
## rate, proximity and optional physics line-of-sight gates all passed.
func _claim_lore(player_id: String, item_id: String) -> Dictionary:
	if player_id != PLAYER_ID or item_id != str(_collectible.get("id", "")):
		return _fail("UNKNOWN_COLLECTIBLE")
	if _lore_claimed:
		return _fail("ALREADY_COLLECTED")
	# EXP016 A11 adds an opt-in authenticated source-research requirement.
	# Original optional-job gate and unchanged lore receipt are still mandatory.
	if advanced_cases != null and \
			not advanced_cases.definition_snapshot().get("source_discovery", {}).is_empty() and \
			not advanced_cases.discovery_ready():
		return _fail("EXP016_A11_LORE_SOURCE_RESEARCH_REQUIRED")
	if not _completed.has(str(_tasks[3]["id"])):
		return _fail("DISCOVERY_EVIDENCE_REQUIRED")
	_lore_claimed = true
	if _account_key != "":
		var receipt: Dictionary = Ledger.make_receipt(_account_key,
			str(_definitions["level_id"]), item_id, "lore")
		var single: Array[Dictionary] = [receipt]
		_reward_queue.issue(single)
	return {"ok": true, "collected_id": item_id}


func _lore_state() -> Dictionary:
	return {"id": str(_collectible.get("id", "")), "collected": _lore_claimed}


## Only accepted new task facts become personal field-point receipts.
func _issue_task_rewards() -> void:
	if _account_key == "":
		return
	var batch: Array[Dictionary] = []
	for task: Dictionary in _tasks:
		var id: String = str(task["id"])
		if _completed.has(id) and not _issued.has(id):
			_issued[id] = true
			batch.append(Ledger.make_receipt(_account_key,
				str(_definitions["level_id"]), id, str(task["kind"])))
	if not batch.is_empty():
		_reward_queue.issue(batch)


## Only the trusted local host calls the pending-receipt/ack interface.
func pending_rewards(account_key: String) -> Array[Dictionary]:
	if account_key == "" or account_key != _account_key:
		return [] as Array[Dictionary]
	return _reward_queue.pending_for(account_key)


func ack_reward(account_key: String, receipt_key: String) -> void:
	if _account_key != "" and account_key == _account_key:
		_reward_queue.ack(account_key, receipt_key)


func lore_state() -> Dictionary:
	return _lore_state().duplicate(true)


func _host_position(player_id: String) -> Vector3:
	if not _position_source.is_valid() or player_id != PLAYER_ID:
		return Vector3.INF
	var candidate: Variant = _position_source.call(player_id)
	if not candidate is Vector3:
		return Vector3.INF
	var position: Vector3 = candidate
	if not position.is_finite() or position.x < 0.0 or position.x > 52.0 or \
			position.z < 0.0 or position.z > 52.0 or position.y < -1.0 or position.y > 10.0:
		return Vector3.INF
	return position


func _position_cm(player_id: String) -> Vector3i:
	var position: Vector3 = _host_position(player_id)
	if position == Vector3.INF:
		return Vector3i.ZERO
	return Vector3i(roundi(position.x * 100.0), roundi(position.y * 100.0),
		roundi(position.z * 100.0))


func _in_range(player_id: String, entity_id: String) -> bool:
	var positions: Dictionary = _definitions.get("positions", {})
	if not positions.has(entity_id):
		return false
	var body: Vector3 = _host_position(player_id)
	if body == Vector3.INF:
		return false
	var origin: Vector3 = body + Vector3.UP * 0.85
	var target: Vector3 = positions[entity_id]
	var radius: float = SWITCH_RADIUS_M if entity_id.begins_with("SW_") else PANEL_RADIUS_M
	if origin.distance_to(target) > INTERACTION_REACH_M + radius:
		return false
	# A physical scene must provide its real physics LoS callback; do not
	# substitute a client boolean. Headless source tests measure range only.
	if _physics_visibility.is_valid():
		return _physics_visibility.call(origin, target, radius)
	return true


func _inside_extraction(player_id: String) -> bool:
	var body: Vector3 = _host_position(player_id)
	if body == Vector3.INF:
		return false
	var center: Vector3 = _definitions["positions"]["ZONE_EXTRACT"]
	return Vector2(body.x - center.x, body.z - center.z).length() <= EXTRACTION_RADIUS_M \
		and absf(body.y - 0.90) <= 1.1


## The host alone owns time. Its zone presence comes from the authoritative
## position provider; neither an RPC nor a client task report can set it.
func tick_host() -> Dictionary:
	if not _ready:
		return _fail("SESSION_NOT_READY")
	_tick += 1
	host.set_in_zone(PLAYER_ID, "ZONE_EXTRACT", _inside_extraction(PLAYER_ID))
	host.tick(_tick)
	if bespoke != null:
		bespoke.advance(_host_position(PLAYER_ID),
			_definitions["positions"]["R_WEST"],
			grid.canonical_state(), interaction.canonical_state()["repairs"])
	_update_progress()
	return {"ok": true, "tick": _tick, "revision": host.revision,
		"completed": completed()}


func _update_progress() -> void:
	if not _ready:
		return
	var bindings: Dictionary = _definitions["bindings"]
	var first: String = str(_tasks[0]["id"])
	var second: String = str(_tasks[1]["id"])
	var third: String = str(_tasks[2]["id"])
	var optional: String = str(_tasks[3]["id"])
	var last: String = str(_tasks[4]["id"])
	var meter_snapshots: Dictionary = meter.canonical_state()["snapshots"]
	var state: Dictionary = grid.canonical_state()
	var repairs: Dictionary = interaction.canonical_state()["repairs"]
	if _observed_inspections.has("PANEL_WEST") and meter_snapshots.has("PANEL_WEST"):
		_completed[first] = true
	if _completed.has(first) and bool(state["edges"]["E_GRID_EAST"]["enabled"]):
		_completed[second] = true
	if _completed.has(second) and str(repairs["R_WEST"]["state"]) == "restored" and \
			not bool(state["nodes"]["WEST"]["failed"]) and \
			not bool(state["nodes"]["WEST"]["tripped"]):
		_completed[third] = true
	if _observed_inspections.has("PANEL_SPUR") and meter_snapshots.has("PANEL_SPUR"):
		_completed[optional] = true
	if _completed.has(first) and _completed.has(second) and _completed.has(third) and \
			not mission.results().is_empty() and \
			(regional_network == null or regional_network.site_prepared()):
		_completed[last] = true
	# Original EXP04 reward receipts cannot precede an opt-in EXP016 interlock.
	if advanced_cases != null and not advanced_cases.solved():
		return
	_issue_task_rewards()


## Read-only per-run task projection; preview field_points are NEVER granted.
func task_board() -> Dictionary:
	if not _ready:
		return _fail("SESSION_NOT_READY")
	var out: Array[Dictionary] = []
	var required_done: int = 0
	for task: Dictionary in _tasks:
		var done: bool = _completed.has(str(task["id"]))
		if done and task["required"]:
			required_done += 1
		out.append({
			"id": task["id"], "kind": task["kind"], "title": task["title"],
			"required": task["required"], "completed": done,
			"state": "done" if done else "optional" if not task["required"] else "pending",
			"binding": (_definitions["bindings"] as Dictionary)[task["id"]]["entity"]
		})
	var board: Dictionary = {
		"ok": true, "schema": RUNTIME_SCHEMA, "level_id": _definitions["level_id"],
		"tasks": out, "required_completed": required_done,
		"required_total": 4, "optional_completed": _completed.has(str(_tasks[3]["id"])),
		"lore_collected": _lore_claimed, "lore_id": str(_collectible.get("id", "")),
		"mission_verified": mission.verified(),
		"mission_completed": completed(),
		"host_revision": host.revision,
		"not_certified": "NO_PHYSICAL_PLAYABILITY_OR_REWARD_PROMOTION"
	}
	if bespoke != null:
		board["bespoke"] = bespoke.snapshot()
	if devices != null:
		board["devices"] = devices.snapshot()
	if faults != null:
		board["faults"] = faults.snapshot()
	if consequences != null:
		board["consequences"] = consequences.snapshot()
	if logistics != null:
		board["logistics"] = logistics.snapshot()
	if balancing != null:
		board["balancing"] = balancing.snapshot()
	if worksite != null:
		board["worksite"] = _worksite_snapshot()
	if advanced_cascade != null:
		board["advanced_cascade"] = advanced_cascade.snapshot()
	if advanced_cases != null:
		board["advanced_cases"] = advanced_cases.snapshot()
	if regional_network != null:
		board["regional_network"] = regional_network.snapshot()
	return board


func authoritative_state() -> Dictionary:
	if not _ready:
		return {}
	var state: Dictionary = host.authoritative_state().duplicate(true)
	if bespoke != null:
		state["exp06"] = bespoke.snapshot()
	if regional_network != null:
		state["exp014_regional_network"] = regional_network.snapshot()
	return state


func state_hash() -> String:
	if not _ready:
		return ""
	if bespoke != null:
		return JSON.stringify(authoritative_state()).sha256_text()
	return host.state_hash()


func completed() -> bool:
	if not _ready or mission.results().is_empty():
		return false
	if advanced_cases != null and not advanced_cases.solved():
		return false
	if regional_network != null:
		return _tasks.size() == 5 and _completed.has(str(_tasks[4]["id"]))
	return true
