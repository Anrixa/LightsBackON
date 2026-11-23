extends SceneTree
## Replays a solution trace and checks it solves.
##
## Contract mode (default): replays a contract's host-intent trace through the host and checks the mission completes
## within max_ticks.
##   godot --headless --path . -s "$PWD/tools/godot/validate_solution.gd" -- --contract=res://content/contracts/c01_alder_street
## Exit 0 = solved, 1 = not solved (mismatches printed), 2 = content errors.
##
## Challenge mode (RB03, ADR-019): replays challenge solution traces through scripts/simulation/challenge_runner.gd at
## every crew size and prints one record per step, tab-separated, for tools/rb03_challenge_check.py to compare with
## the Python reference byte for byte:
##   STEP  <challenge> <crew> <index> <do> <outcome> <tick> <sha256>
##   FINAL <challenge> <crew> <solved_tick> <sha256> <canonical string>
##   godot --headless --path . -s "$PWD/tools/godot/validate_solution.gd" -- --challenge=<file> --trace=<file>
##   godot --headless --path . -s "$PWD/tools/godot/validate_solution.gd" -- --manifest=<file>   (JSON [{challenge, trace}])
## Exit 0 = every trace solved at every crew size with every step's expected outcome, 1 = not, 2 = content errors.

const Runner := preload("res://tests/support/solution_runner.gd")
const ChallengeRunner := preload("res://scripts/simulation/challenge_runner.gd")
const RULES_PATH: String = "res://content/challenges/rules.json"


func _initialize() -> void:
	var dir: String = "res://content/contracts/c01_alder_street"
	var pairs: Array[Dictionary] = []
	var challenge: String = ""
	var trace_path: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--contract="):
			dir = a.trim_prefix("--contract=")
		elif a.begins_with("--challenge="):
			challenge = a.trim_prefix("--challenge=")
		elif a.begins_with("--trace="):
			trace_path = a.trim_prefix("--trace=")
		elif a.begins_with("--manifest="):
			for p: Variant in JSON.parse_string(FileAccess.get_file_as_string(a.trim_prefix("--manifest="))):
				pairs.append(p)
	if challenge != "":
		pairs.append({"challenge": challenge, "trace": trace_path})
	if not pairs.is_empty():
		quit(_challenges(pairs))
		return
	var trace: Dictionary = Runner.json(dir.path_join("solution.json"))
	var ctx: Dictionary = Runner.build(dir, trace["players"], trace["tools"])
	if not (ctx["errors"] as Array).is_empty():
		print("CONTENT ERRORS: %s" % str(ctx["errors"]))
		quit(2)
		return
	var failures: Array[String] = Runner.run(ctx, trace["steps"], int(trace.get("pace_ticks_per_command", 0)))
	var done: bool = ctx["mission"].is_complete()
	if done and failures.is_empty() and int(ctx["now"]) <= int(trace["max_ticks"]):
		print("SOLVED %s in %d ticks (%d steps)" % [trace["contract_id"], int(ctx["now"]), (trace["steps"] as Array).size()])
		quit(0)
		return
	for f: String in failures:
		print("MISMATCH " + f)
	print("NOT SOLVED %s: complete=%s ticks=%d" % [trace["contract_id"], str(done), int(ctx["now"])])
	quit(1)


func _challenges(pairs: Array[Dictionary]) -> int:
	var rules: Dictionary = ChallengeRunner.json(RULES_PATH)
	var status: int = 0
	for pair: Dictionary in pairs:
		var doc: Dictionary = ChallengeRunner.json(pair["challenge"])
		var trace: Dictionary = ChallengeRunner.json(pair["trace"])
		var cid: String = str(doc.get("id", "?"))
		for crew: String in ChallengeRunner.CREWS:
			var run: ChallengeRunner = ChallengeRunner.new()
			var errs: Array[Dictionary] = run.load_challenge(doc, rules, crew)
			if not errs.is_empty():
				print("CONTENT ERRORS %s: %s" % [cid, str(errs)])
				return 2
			var index: int = 0
			for step: Dictionary in trace["steps"]:
				var got: String = run.do_step(step)
				print("\t".join(PackedStringArray(["STEP", cid, crew, str(index), str(step.get("do")), got, str(run.now()),
					run.canonical_hash()])))
				if got != str(step.get("expect", "ok")):
					status = 1
				index += 1
			var want: Variant = (trace.get("solved_ticks", {}) as Dictionary).get(crew)
			if (run.solved_tick == ChallengeRunner.UNSOLVED and trace.get("must_solve", true)) 					or (want != null and int(want) != run.solved_tick):
				status = 1
			print("\t".join(PackedStringArray(["FINAL", cid, crew, str(run.solved_tick), run.canonical_hash(),
				run.canonical_string()])))
	return status
