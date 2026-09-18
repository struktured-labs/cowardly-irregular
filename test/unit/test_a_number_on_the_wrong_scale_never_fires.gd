extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

## Whole-surface autoload restore — this file left autoload state for every later file.
var _ag_state: Dictionary

## The grind grammar said "Numeric conditions take op ∈ {…} and value" and named no UNITS,
## so the model answered in the units it assumed. A value on the wrong scale validates
## clean, reaches the player, and never fires.
##
## MEASURED on live llama3 2026-09-17. The time arm is a CONTROLLED pair — the same two
## intents, 12 samples each, the only difference being this block:
##
##     time_elapsed   without the block   14 of 14 off-scale, every one `3600`
##                    with the block       0 of 12, every one `60`
##
## The evaluator computes MINUTES (`elapsed_min = (now - start) / 60.0`), so 3600 is
## sixty hours. A player asking to grind "about an hour" got a rule that never fires.
##
## ⚠️ corruption is OBSERVATIONAL, not controlled: 9 of 17 values across the other corpora
## were 10/20/30/50 — percent thinking on a float where 4.5 stops the session — but the
## controlled pair emitted only one corruption condition, which is too few to test. Stated
## as what it is rather than folded into the headline.
##
## party_hp_* needed nothing: 10-90 throughout. The model infers percent from the name, and
## naming it costs one line and removes the assumption.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const RC := preload("res://src/llm/RuleComposer.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func _rc():
	var c = RC.new()
	if c is Node:
		add_child_autofree(c)
	return c


func _sys():
	var s = get_tree().root.get_node_or_null("AutogrindSystem")
	assert_not_null(s, "CONTROL: AutogrindSystem autoload must exist")
	return s


func _grind(scales: Dictionary) -> String:
	var ctx := {"resolved": true, "party": [
		{"member": "cleric", "job_id": "cleric", "kit": ["cure"], "costs": {"cure": 6},
		"profiles": ["Default"], "between_battle": ["cure"]}]}
	if not scales.is_empty():
		ctx["scales"] = scales
	return DP.build_rule_composition("autogrind", "grind a while", [], ctx)


# ── the defect ────────────────────────────────────────────────────────────────

func test_the_prompt_says_what_time_elapsed_is_measured_in() -> void:
	## THE ARM. 14 of 14 emitted `3600` without it.
	var p: String = _grind({"corruption_limit": 4.5, "efficiency_start": 1.0})
	var at: int = p.find("WHAT THE NUMBERS MEAN")
	assert_gt(at, -1, "the scale block must render")
	assert_true(p.substr(at).find("MINUTES") != -1, "time_elapsed's unit must be named")
	assert_true(p.substr(at).find("NOT seconds") != -1,
		"and the unit the model assumes must be named as wrong — that is the whole finding")


func test_the_evaluator_really_does_work_in_minutes() -> void:
	## THE RATCHET. The prompt now makes a claim ABOUT THE ENGINE. If the evaluator stops
	## dividing by 60, the prompt is confidently teaching the wrong unit and nothing else
	## would notice. Comments stripped, because one of them says "minutes" in prose.
	var code: String = GdSource.code_of("res://src/autogrind/AutogrindSystem.gd")
	assert_false(code.is_empty(), "CONTROL: the source must be readable")
	## The MATCH ARM, not the display-name table: the label map has `"time_elapsed": "Time
	## Elapsed",` on one line and appears FIRST, so a bare find() lands there and the arm
	## fails on a string that was never the subject. It did, before this anchor.
	var at: int = code.find("\"time_elapsed\":\n")
	assert_gt(at, -1, "CONTROL: the time_elapsed match arm must still be findable")
	var arm: String = code.substr(at, 400)
	assert_true(arm.find("/ 60.0") != -1,
		"the prompt says MINUTES because the evaluator divides by 60: %s" % arm.substr(0, 200))


func test_the_corruption_stopping_point_is_the_engines_own_number() -> void:
	## Written into the prompt it would drift from the number that actually ends a session.
	## Read from interrupt_rules it cannot.
	## ⚠️ Comparing the composer's answer to the engine's CURRENT value cannot fail while a
	## hardcoded 4.5 equals the engine's default 4.5 — the mutation that hardcodes it
	## survived exactly that arm. The engine's value has to MOVE for the read to be tested.
	var sys = _sys()
	sys._test_disable_persistence = true
	var original: float = float(sys.interrupt_rules.get("corruption_limit", 4.5))
	sys.interrupt_rules["corruption_limit"] = 7.25
	var scales: Dictionary = _rc()._numeric_scales()
	var rendered: String = _grind(scales)
	sys.interrupt_rules["corruption_limit"] = original
	assert_eq(float(scales.get("corruption_limit", -1.0)), 7.25,
		"the composer must READ the engine's value, not carry a copy that matches its default")
	assert_true(rendered.find("stops itself at 7.25") != -1,
		"and the rendered line must carry what it read")


func test_a_changed_stopping_point_changes_the_prompt() -> void:
	## The mutation a hardcoded 4.5 would survive.
	var p: String = _grind({"corruption_limit": 9.0, "efficiency_start": 1.0})
	assert_true(p.find("stops itself at 9") != -1, "the block follows the engine: %s"
		% p.substr(maxi(0, p.find("corruption")), 120))


# ── controls ──────────────────────────────────────────────────────────────────

func test_no_scales_renders_no_block() -> void:
	## Headless and any caller that cannot resolve AutogrindSystem. A heading promising
	## units with none under it is the shape this whole branch exists to remove.
	var p: String = _grind({})
	assert_true(p.find("WHAT THE NUMBERS MEAN") == -1, "an absent scale set renders nothing")
	assert_gt(p.length(), 500, "CONTROL: the rest of the prompt still builds")


func test_the_autobattle_prompt_does_not_get_the_grind_scales() -> void:
	## corruption, efficiency and time_elapsed are grind conditions; autobattle's numerics
	## are a different set with their own documented ranges.
	var p: String = DP.build_rule_composition("autobattle", "fight well", [],
		{"resolved": true, "job_id": "mage", "kit": ["fire"], "full_kit": ["fire"],
		"max_mp": 70, "costs": {"fire": 8}})
	assert_true(p.find("WHAT THE NUMBERS MEAN") == -1, "the grind scale block must not leak")


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()


func after_each() -> void:
	AutogrindState.restore(_ag_state)


# ── the block cannot fall behind the engine's list ─────────────────────────────

func test_every_numeric_condition_is_given_a_unit() -> void:
	## time_elapsed and corruption were each named only AFTER the model had already
	## guessed their scale wrong. The block is hand-written and NUMERIC_CONDITIONS is
	## engine-owned, so a fourteenth entry gets no unit and the guess happens a third
	## time — silently, because a wrong scale validates, delivers, and never fires.
	var sys = _sys()
	var nums: Array = sys.NUMERIC_CONDITIONS
	assert_gt(nums.size(), 0, "FLOOR: an empty list would make the loop below vacuous")
	var p: String = _grind({"corruption_limit": 4.5, "efficiency_start": 1.0})
	var at: int = p.find("WHAT THE NUMBERS MEAN")
	assert_gt(at, -1, "the scale block must render")
	## Sliced to the block. The grammar above lists every type by NAME, so the same
	## search run against the whole prompt is satisfied with no units rendered at all.
	var block: String = p.substr(at)
	var ends: int = block.find("STATUS IDS")
	if ends > -1:
		block = block.substr(0, ends)
	var unnamed: Array[String] = []
	for c in nums:
		if block.find(str(c)) == -1:
			unnamed.append(str(c))
	assert_eq(unnamed.size(), 0,
		"every numeric condition needs its unit stated; these carry none: %s" % [unnamed])


func test_the_grammar_names_every_numeric_so_a_prompt_wide_search_is_vacuous() -> void:
	## CONTROL for the arm above, and the reason it slices. Every numeric condition is
	## named in the grammar's own type list, so a prompt with the units block ABSENT
	## still contains all 13 names — the naive check reports full coverage of nothing.
	var sys = _sys()
	var nums: Array = sys.NUMERIC_CONDITIONS
	assert_gt(nums.size(), 0, "FLOOR: an empty list would make the loop below vacuous")
	var without: String = _grind({})
	assert_eq(without.find("WHAT THE NUMBERS MEAN"), -1, "CONTROL: no scales, no block")
	var found_anyway: int = 0
	for c in nums:
		if without.find(str(c)) != -1:
			found_anyway += 1
	assert_eq(found_anyway, nums.size(),
		"the grammar list alone names every numeric condition — %d of %d, which is why the arm above slices to the block" % [found_anyway, nums.size()])
