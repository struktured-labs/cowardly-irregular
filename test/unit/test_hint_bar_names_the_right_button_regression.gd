extends GutTest

## The hint bar tells the player which button does what. Nothing checked that it was true.
## PROFILE_ULTIMATE_PRO_2 had Defer and Advance inverted against this string for a week with
## every guard green — the label is rendered, the binding is read, and the two never met.
## Constants are read via get_script_constant_map(), never regex: a source pin is a claim
## about spelling, and this is a claim about agreement.

const HINT_OWNER := "res://src/ui/Win98Menu.gd"
const PROFILES_OWNER := "res://src/input/InputProfileManager.gd"

## Each hint-bar phrase and the input action it promises. The test asserts the promise,
## so a claim whose action disappears fails here rather than on the player's couch.
const CLAIM_TO_ACTION := {
	"Defer": "battle_defer",
	"Advance": "battle_advance",
	"Auto": "battle_toggle_auto",
}

## Claims with no input action at all — the button is compared raw in an `if`, so nothing
## can resolve the label against a binding. Speed is checked against JOY_BUTTON_Y directly
## in BattleScene._unhandled_input. Listed so a NEW unbacked claim fails, and so this entry
## goes stale loudly if Speed ever gains an action.
const CLAIMS_WITHOUT_ACTIONS := ["Speed"]


func _consts(path: String) -> Dictionary:
	var script: Script = load(path)
	assert_not_null(script, "%s must load — without it this proves nothing" % path)
	return script.get_script_constant_map() if script else {}


func _hint_text() -> String:
	return str(_consts(HINT_OWNER).get("HINT_DEFAULT_TEXT", ""))


## [Token] Phrase -> {"Phrase": "Token"}. Parsed from the shipped string, not a copy of it.
func _claims() -> Dictionary:
	var out := {}
	var rx := RegEx.new()
	rx.compile("\\[([^\\]]+)\\]\\s*([A-Za-z]+)")
	for m in rx.search_all(_hint_text()):
		out[m.get_string(2)] = m.get_string(1)
	return out


func test_the_parse_finds_the_shipped_claims() -> void:
	var text := _hint_text()
	assert_gt(text.length(), 0, "HINT_DEFAULT_TEXT must be readable — an empty read makes every assertion below vacuous")
	var claims := _claims()
	assert_gt(claims.size(), 2, "the parser must find the hint bar's claims: %s" % str(claims))
	assert_true(claims.has("Defer"), "control: 'Defer' is a known-present claim and must parse: %s" % str(claims))
	assert_false(claims.has("Zzznope"), "control: an invented phrase must not parse")


## The load-bearing test. Every claim with an action must name the button that action is bound to.
func test_every_claim_names_the_button_its_action_is_bound_to() -> void:
	var profiles := _consts(PROFILES_OWNER)
	var standard: Dictionary = profiles.get("PROFILE_STANDARD", {})
	var labels: Dictionary = profiles.get("BUTTON_LABELS", {})
	assert_gt(standard.size(), 0, "PROFILE_STANDARD must be readable")
	assert_gt(labels.size(), 0, "BUTTON_LABELS must be readable")

	var claims := _claims()
	var wrong: Array[String] = []
	for phrase in CLAIM_TO_ACTION:
		var action: String = CLAIM_TO_ACTION[phrase]
		if not claims.has(phrase):
			wrong.append("%s: the hint bar no longer claims it" % phrase)
			continue
		if not standard.has(action):
			wrong.append("%s: '%s' is not bound in PROFILE_STANDARD" % [phrase, action])
			continue
		var advertised: String = claims[phrase]
		var bound: Array = standard[action]
		var matched := false
		for idx in bound:
			var label: String = str(labels.get(int(idx), ""))
			for part in label.split("/"):
				if part.strip_edges().begins_with(advertised):
					matched = true
		if not matched:
			var names := []
			for idx in bound:
				names.append(str(labels.get(int(idx), "?")))
			wrong.append("the hint bar says [%s] %s, but %s is bound to %s" % [advertised, phrase, action, str(names)])
	assert_eq(wrong, [] as Array[String],
		"the hint bar names a button that does something else — the player reads this string and presses that button: %s" % str(wrong))


## A claim with no action cannot be checked against a binding, so it is pinned by name.
## Adding an unbacked claim fails here; so does removing one, which means this list expires.
func test_unbacked_claims_are_exactly_the_pinned_set() -> void:
	var claims := _claims()
	var unbacked: Array[String] = []
	for phrase in claims:
		if not CLAIM_TO_ACTION.has(phrase):
			unbacked.append(str(phrase))
	unbacked.sort()
	var expected: Array[String] = []
	for c in CLAIMS_WITHOUT_ACTIONS:
		expected.append(str(c))
	expected.sort()
	assert_eq(unbacked, expected,
		"a hint-bar claim has no input action, so nothing can verify it names the right button. Either bind it, or add it here with a reason: %s" % str(unbacked))


## Speed's letter is layout-dependent: JOY_BUTTON_Y is NORTH, printed X on Nintendo pads
## (struktured's 8BitDo) and Y on Xbox pads. The string is right for his hardware and wrong
## for the other layout. Pinned so a rebind or a relabel surfaces the coupling.
func test_speed_is_still_the_north_button_and_still_unbound() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_gt(src.length(), 0, "BattleScene.gd must be readable")
	assert_true(src.contains("JOY_BUTTON_Y:\n\t\t\t_toggle_battle_speed()") or src.contains("== JOY_BUTTON_Y"),
		"battle speed is expected to read JOY_BUTTON_Y (NORTH) directly — if it moved to an action, delete this test and add Speed to CLAIM_TO_ACTION")
	var profiles := _consts(PROFILES_OWNER)
	var labels: Dictionary = profiles.get("BUTTON_LABELS", {})
	assert_true(str(labels.get(3, "")).contains("Nintendo X"),
		"index 3 must still be documented as the button printed X on Nintendo pads — the hint bar's [X] depends on it")
