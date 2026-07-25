extends GutTest

## Cycle 21 (cowir-ai msg 2916/2959) — `is_night` autobattle condition,
## evaluator half. cowir-ai owns the grammar half (the Rule Composer
## vocabulary + fizzle deep-check) and is holding it until this lands.
##
## RULING (cowir-ai as grammar owner, and the reasoning is binding on
## this implementation): nullary, night-band ONLY.
##
## The binding reason isn't preference — `GameState.is_night()` already
## exists and returns `get_time_of_day_name() == "night"`. If the rule
## vocabulary's `is_night` meant night-OR-dusk, the project would ship
## two things named `is_night` with different truth conditions, one in
## GDScript and one in the player-facing grammar. A player reads the
## condition name, reasons from observed game behaviour, and writes a
## rule that fires on a band they didn't expect. That's a lying name —
## the same silent-failure class this repo keeps stamping out.
##
## Parameterized `{type:"time_of_day", band:"dusk"}` was considered and
## rejected: the Rule Composer LLM authors these, and a band string can
## be MALFORMED ("midnight", "evening"), needing an allowlist in the
## fizzle deep-check with a fresh silent-never-fires mode if the
## allowlist is wrong. A nullary is unmalformable by construction.
## If "at dusk" is ever wanted, it's a second nullary sibling.
##
## LOAD ORDER (why the evaluator lands first): every condition type
## referenced by a rule template must resolve in the evaluator's
## supported list, or templates silently install rules that can never
## fire. Evaluator -> grammar -> any template using it.

const AS_PATH: String = "res://src/autobattle/AutobattleSystem.gd"
const GS_PATH: String = "res://src/meta/GameState.gd"


## Extract the is_night match arm by its BOUNDARIES (arm start -> the
## next arm, "always") rather than a fixed character count. A fixed
## window is a coincidental magnitude: it passes only while the arm's
## comment happens to be shorter than the number, and it broke twice
## during authoring as the comment grew. Boundary-based extraction is
## the relationship the assertions actually care about.
func _is_night_arm_body(src: String) -> String:
	var start: int = src.find("\t\t\"is_night\":")
	if start == -1:
		return ""
	var end: int = src.find("\t\t\"always\":", start)
	if end == -1:
		end = src.length()
	return src.substr(start, end - start)


## ── (1) Registered in the condition-type registry ────────────────────

func test_is_night_registered_in_condition_types() -> void:
	# CONDITION_TYPES is what validate_rule and the grid editor check
	# against. Unregistered means a rule using it fails validation even
	# with a working evaluator arm.
	var src: String = FileAccess.get_file_as_string(AS_PATH)
	var start: int = src.find("const CONDITION_TYPES = {")
	assert_gt(start, -1, "CONDITION_TYPES registry must exist")
	var end: int = src.find("}", start)
	var block: String = src.substr(start, end - start)
	assert_string_contains(block, "\"is_night\"",
		"is_night must be registered in CONDITION_TYPES or validate_rule rejects rules using it")


func test_is_night_has_a_display_label() -> void:
	# The registry doubles as the grid editor's label source; a missing
	# label renders an unlabelled row.
	var src: String = FileAccess.get_file_as_string(AS_PATH)
	assert_string_contains(src, "\"is_night\": \"Is Night\"",
		"is_night needs a human-readable label for the grid editor")


## ── (2) The evaluator arm ────────────────────────────────────────────

func test_is_night_evaluator_arm_exists() -> void:
	var src: String = FileAccess.get_file_as_string(AS_PATH)
	assert_string_contains(src, "\"is_night\":",
		"the string evaluator must have an is_night match arm")


func test_is_night_delegates_to_game_state() -> void:
	# The truth condition must BE GameState.is_night(), not a
	# reimplementation. A local reimplementation is exactly how the two
	# meanings would drift apart later.
	var src: String = FileAccess.get_file_as_string(AS_PATH)
	var window: String = _is_night_arm_body(src)
	assert_ne(window, "", "is_night arm must be findable")
	assert_string_contains(window, "gs.is_night()",
		"must delegate to GameState.is_night() — never reimplement the band test")


func test_is_night_does_not_reimplement_band_logic() -> void:
	# Guard the drift directly: no day_phase arithmetic, no band-name
	# string comparison in the arm.
	var src: String = FileAccess.get_file_as_string(AS_PATH)
	var window: String = _is_night_arm_body(src)
	assert_ne(window, "", "is_night arm must be findable")
	assert_false(window.find("day_phase") > -1,
		"must not read day_phase directly — that's GameState's business and duplicating it invites drift")
	assert_false(window.find("get_time_of_day_name") > -1,
		"must not band-compare by name either — is_night() already encapsulates that")


func test_is_night_is_nullary_no_operator_or_value() -> void:
	# Nullary by construction: the arm must not consult compare_op or
	# value. If it did, a malformed rule could produce surprising truth.
	var src: String = FileAccess.get_file_as_string(AS_PATH)
	var window: String = _is_night_arm_body(src)
	assert_ne(window, "", "is_night arm must be findable")
	assert_false(window.find("_compare(") > -1,
		"is_night is nullary — it must not run a comparison")
	assert_false(window.find("compare_op") > -1,
		"is_night must not consult compare_op")


func test_is_night_safe_without_game_state() -> void:
	# Headless/test contexts may lack the autoload. Returning false
	# (rather than crashing or defaulting true) means a night-gated rule
	# simply doesn't fire, which is the conservative direction — it
	# falls through to the next rule rather than firing wrongly.
	var src: String = FileAccess.get_file_as_string(AS_PATH)
	var window: String = _is_night_arm_body(src)
	assert_ne(window, "", "is_night arm must be findable")
	assert_string_contains(window, "gs == null",
		"must guard a missing GameState autoload")
	assert_string_contains(window, "has_method(\"is_night\")",
		"must guard against GameState lacking the method")


## ── (3) The cross-lane contract with GameState ───────────────────────

func test_game_state_is_night_exists_and_is_night_only() -> void:
	# The whole ruling rests on GameState.is_night() meaning NIGHT ONLY.
	# If someone later widens it to include dusk, the grammar term
	# silently widens too and the name stops matching player
	# expectation — so pin the definition, not just its existence.
	var src: String = FileAccess.get_file_as_string(GS_PATH)
	assert_string_contains(src, "func is_night() -> bool:",
		"GameState.is_night must exist — the autobattle condition delegates to it")
	assert_string_contains(src, "return get_time_of_day_name() == \"night\"",
		"is_night must remain NIGHT-ONLY — widening it to include dusk would silently widen the autobattle grammar term of the same name (cowir-ai's ruling, msg 2959)")


## ── (4) Load-order guard: no template may reference it prematurely ───

func test_no_rule_template_uses_is_night_yet() -> void:
	# Evaluator -> grammar -> templates. A template referencing a
	# condition the evaluator doesn't support installs rules that never
	# fire, silently (the failure class cowir-autogrind hit at their
	# task #2). The evaluator now supports it, so this guard exists to
	# document the ordering rather than to block forever — when a
	# nocturnal preset IS authored, delete this test in that commit.
	var f: FileAccess = FileAccess.open("res://data/autobattle_rule_templates.json", FileAccess.READ)
	if f == null:
		pass_test("no template file — nothing to order against")
		return
	var text: String = f.get_as_text()
	assert_false(text.find("is_night") > -1,
		"no template references is_night yet — when one is authored, confirm the grammar half landed first and delete this ordering guard in that same commit")
