extends GutTest

## A benchmark that measures an approximation of a prompt measures the approximation.
## tools/llm_prompt_bench.gd renders through DialoguePrompts, and rebuilds the kit context
## by hand — because a `-s` script has no autoloads, so it cannot call
## AutobattleSystem.get_deep_check_kit.
##
## That hand-built shape is the one thing that can drift silently: the kit block is a large
## part of an autobattle prompt, and a bench feeding a stale shape would report numbers for
## a prompt the game never sends — while looking perfectly healthy.
##
## So: compare the bench's shape against the live function's, key by key.

const BENCH_RENDERER := "res://tools/llm_prompt_bench.gd"
const BENCH_DRIVER := "res://tools/llm_prompt_bench.py"


func test_the_bench_kit_shape_matches_the_live_one() -> void:
	var abs_sys = get_tree().root.get_node_or_null("AutobattleSystem")
	assert_not_null(abs_sys, "CONTROL: AutobattleSystem must be reachable")
	var live: Dictionary = abs_sys.get_deep_check_kit("hero")
	assert_true(bool(live.get("resolved", false)), "CONTROL: the live kit must resolve for hero")

	var src: String = FileAccess.get_file_as_string(BENCH_RENDERER)
	assert_false(src.is_empty(), "CONTROL: the bench renderer must be readable")
	var missing: Array = []
	for key in live:
		if src.find("\"%s\"" % str(key)) == -1:
			missing.append(str(key))
	assert_eq(missing, [],
		"the bench builds a kit context by hand; these keys exist in the live one and not in it: %s"
			% str(missing))


func test_the_bench_refuses_a_kit_that_did_not_resolve() -> void:
	## This file's own premise — "a bench feeding a stale shape would report numbers for a
	## prompt the game never sends, while looking perfectly healthy" — had no arm for the
	## DEGRADED case, only for the shape. Every route to an empty kit is a failed read that
	## says nothing: the three FileAccess.open helpers return [] on null, and _kit_for parses
	## jobs.json into a typed Dictionary, so an unreadable file yields null and the assignment
	## ABORTS the function. Measured with jobs.json pointed at a missing path, pre-fix:
	## EC=0, 9 prompts rendered, 10 files written, fighter_basic.txt 7306 chars against a good
	## render's ~9280 and naming not one fighter ability.
	var src: String = FileAccess.get_file_as_string(BENCH_RENDERER)
	assert_gt(src.length(), 1000,
		"CONTROL: %s must actually be read, or this arm asserts over ''" % BENCH_RENDERER)
	var build: int = src.find("DP.build_rule_composition(")
	var guard: int = src.find("kc.get(\"resolved\", false)")
	assert_gt(build, -1, "the bench must still render through build_rule_composition")
	assert_gt(guard, -1, "the bench must check that the kit context resolved")
	assert_lt(guard, build,
		"the resolved check must precede the render, or a degraded prompt is written anyway")


func test_every_data_read_goes_through_the_guarded_reader() -> void:
	## The floor above catches an unresolved KIT, and that was not enough: three helpers
	## returned [] when FileAccess.open came back null, while _kit_for still reported
	## resolved=true. Measured before this arm — items.json dark gave EC=0, 9 rendered,
	## fighter_basic.txt 8726 chars against ~9280, silently missing its item list.
	## A failed read CANNOT be signalled by an empty result (between_battle is legitimately
	## empty for a kit with no healing), so the reader records it and the floor reads that.
	var src: String = FileAccess.get_file_as_string(BENCH_RENDERER)
	assert_gt(src.length(), 1000,
		"CONTROL: %s must actually be read, or this arm asserts over ''" % BENCH_RENDERER)
	var stray: Array = []
	var at: int = src.find("\"res://data/")
	while at != -1:
		## Every data path must be an ARGUMENT to the guarded reader. A literal reached by
		## FileAccess directly is a read that can fail silently.
		if src.substr(max(0, at - 15), 15).find("_require_json(") == -1:
			stray.append(src.substr(at, src.find("\"", at + 1) - at + 1))
		at = src.find("\"res://data/", at + 1)
	assert_eq(stray, [],
		"these data paths bypass _require_json and can fail silently: %s" % str(stray))
	assert_gt(src.find("_read_failed = true"), -1,
		"the reader must RECORD a failed read — an empty result cannot signal one")
	assert_gt(src.find("if _read_failed or"), -1,
		"the render floor must refuse on a recorded read failure, not only on an unresolved kit")


func test_a_documented_invocation_carries_the_sandbox() -> void:
	## These tools have no wrapper, so the docstring IS the interface. A bare `godot --headless`
	## resolves user:// to the real profile — that is how a sibling lane rotated the player's
	## crash logs away tonight, from a tool whose only possible invocation was bare.
	## Derived over the lane's tools so a fourth one inherits the rule.
	var offenders: Array = []
	for tool_path in ["res://tools/rule_composition_compose.gd",
			"res://tools/rule_composition_validate.gd", "res://tools/llm_prompt_bench.gd"]:
		var src: String = FileAccess.get_file_as_string(tool_path)
		assert_gt(src.length(), 500,
			"CONTROL: %s must actually be read, or this arm skips it" % tool_path)
		for line in src.split("\n"):
			if line.find("godot --headless") == -1:
				continue
			## PRESENCE IS NOT ENOUGH. Measured by a sibling lane after this arm shipped:
			## an INVALID sandbox path fails CLOSED (godot aborts, EC=134, nothing written),
			## but an EMPTY XDG_DATA_HOME is treated as unset per the XDG spec — godot writes
			## the player's REAL profile at EC=0 with no warning. So require a value.
			var at: int = line.find("XDG_DATA_HOME=")
			if at == -1:
				offenders.append("%s :: no sandbox :: %s" % [tool_path.get_file(), line.strip_edges()])
				continue
			var rest: String = line.substr(at + len("XDG_DATA_HOME="))
			var value: String = rest.split(" ")[0].replace("\"", "").replace("'", "")
			if value == "":
				offenders.append("%s :: EMPTY sandbox (fails OPEN onto the real profile) :: %s"
					% [tool_path.get_file(), line.strip_edges()])
	assert_eq(offenders, [],
		"a documented bare godot writes to the player's real user:// — %s" % str(offenders))


func test_the_bench_renders_through_dialogue_prompts() -> void:
	## Not a copy of the prompt text, and not a hand-rolled approximation.
	var src: String = FileAccess.get_file_as_string(BENCH_RENDERER)
	assert_true(src.find("res://src/llm/DialoguePrompts.gd") != -1,
		"the bench must load the real prompt builder")
	assert_true(src.find("build_rule_composition(") != -1,
		"and call it, rather than assembling prompt text of its own")


func test_the_bench_covers_both_domains() -> void:
	## Autogrind has no per-rule rescue, so a prompt change there is the more expensive
	## one to get wrong. A bench that silently covered only autobattle would hide that.
	var src: String = FileAccess.get_file_as_string(BENCH_RENDERER)
	assert_true(src.find("\"autobattle\"") != -1, "autobattle prompts must be rendered")
	assert_true(src.find("\"autogrind\"") != -1, "autogrind prompts must be rendered")


func test_the_driver_samples_sequentially_by_default() -> void:
	## MEASURED 2026-09-16: concurrency changes the malformed-reply rate (1 lost in 30
	## sequential, 4 lost under three workers), and the game issues one request at a time.
	## A bench defaulting to parallel would understate the shipped path — and it is the
	## kind of default nobody revisits.
	var py: String = FileAccess.get_file_as_string(BENCH_DRIVER)
	assert_false(py.is_empty(), "CONTROL: the driver must be readable")
	assert_true(py.find("\"--workers\", type=int, default=1") != -1,
		"the driver must default to one worker")


func test_the_driver_refuses_an_ambiguous_edit() -> void:
	## Both arms must differ by exactly one thing. A --find matching twice would change
	## two places and the result would not say which mattered.
	var py: String = FileAccess.get_file_as_string(BENCH_DRIVER)
	assert_true(py.find("count(args.find) != 1") != -1,
		"the driver must require the edit to match exactly once")


func test_the_driver_reports_significance() -> void:
	## The measurement this lane got wrong twice today looked decisive at one round and
	## was not. The p-value is what stops a ship decision resting on two fractions.
	var py: String = FileAccess.get_file_as_string(BENCH_DRIVER)
	assert_true(py.find("fisher_two_tailed") != -1, "the driver must compute an exact p")
	assert_true(py.find("NOT significant at p<0.05") != -1,
		"and say so plainly when the arms cannot be separated")
