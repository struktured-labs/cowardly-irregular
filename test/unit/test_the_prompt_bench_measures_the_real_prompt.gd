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
