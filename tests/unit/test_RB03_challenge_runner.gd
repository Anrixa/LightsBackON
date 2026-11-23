extends "res://tests/test_case.gd"
## RB03 (ADR-019): the GDScript challenge runner replays the committed golden trace and the refusal probe exactly as the
## Python reference does (pinned final hashes). tools/rb03_challenge_check.py compares every step's bytes as well.

const ChallengeRunner := preload("res://scripts/simulation/challenge_runner.gd")
const DATA: String = "res://tests/data/challenges/"
const RULES: String = "res://content/challenges/rules.json"


func _replay(doc: Dictionary, trace: Dictionary, crew: String) -> Array:
	var run: ChallengeRunner = ChallengeRunner.new()
	var errs: Array[Dictionary] = run.load_challenge(doc, ChallengeRunner.json(RULES), crew)
	assert_eq(errs, [] as Array[Dictionary], "load %s" % crew)
	var outcomes: Array[String] = []
	for step: Dictionary in trace["steps"]:
		outcomes.append(run.do_step(step))
	return [run, outcomes]


func test_RB03_golden_storm_trace_solves_at_every_crew_size() -> void:
	var doc: Dictionary = ChallengeRunner.json(DATA + "rb03_storm_shift.json")
	var trace: Dictionary = ChallengeRunner.json(DATA + "traces/rb03_storm_shift.trace.json")
	for crew: String in ChallengeRunner.CREWS:
		var got: Array = _replay(doc, trace, crew)
		var run: ChallengeRunner = got[0]
		for o: String in got[1]:
			assert_eq(o, "ok", "crew %s" % crew)
		assert_eq(run.solved_tick, int(trace["solved_ticks"][crew]), "solved tick, crew %s" % crew)
		assert_eq(run.canonical_hash(), str(trace["final_hash"][crew]), "final hash equals the Python reference, crew %s" % crew)


func test_SIM10_probe_refusals_match_their_expected_codes() -> void:
	var doc: Dictionary = ChallengeRunner.json(DATA + "rb03_storm_shift.json")
	var probe: Dictionary = ChallengeRunner.json(DATA + "probes/rb03_storm_shift.probe.json")
	var got: Array = _replay(doc, probe, "1")
	var outcomes: Array = got[1]
	var i: int = 0
	for step: Dictionary in probe["steps"]:
		assert_eq(outcomes[i], str(step.get("expect", "ok")), "probe step %d" % i)
		i += 1
	assert_eq((got[0] as ChallengeRunner).solved_tick, ChallengeRunner.UNSOLVED)


func test_SIM11_reversed_record_order_gives_identical_hashes() -> void:
	var doc: Dictionary = ChallengeRunner.json(DATA + "rb03_storm_shift.json")
	var trace: Dictionary = ChallengeRunner.json(DATA + "traces/rb03_storm_shift.trace.json")
	var rev: Dictionary = doc.duplicate(true)
	for key: String in ["nodes", "edges", "protections"]:
		(rev["grid"][key] as Array).reverse()
	for key: String in ["faults", "switches", "latches", "access_routes", "flood_areas", "storm_events", "temporary_supply"]:
		(rev[key] as Array).reverse()
	var a: ChallengeRunner = _replay(doc, trace, "1")[0]
	var b: ChallengeRunner = _replay(rev, trace, "1")[0]
	assert_eq(b.canonical_string(), a.canonical_string())


func test_RB03_bad_challenge_is_refused_before_replay() -> void:
	var doc: Dictionary = ChallengeRunner.json(DATA + "rb03_storm_shift.json")
	doc["grid"]["edges"].append({"id": "E_BACKFEED", "from": "JW", "to": "GRID", "capacity": 1, "enabled": false, "healthy": true})
	var run: ChallengeRunner = ChallengeRunner.new()
	var errs: Array[Dictionary] = run.load_challenge(doc, ChallengeRunner.json(RULES), "1")
	assert_false(errs.is_empty(), "a backfeed into a source must not load")
	doc = ChallengeRunner.json(DATA + "rb03_storm_shift.json")
	errs = ChallengeRunner.new().load_challenge(doc, ChallengeRunner.json(RULES), "5")
	assert_eq(errs.size(), 1, "crew of five is not a crew size")
