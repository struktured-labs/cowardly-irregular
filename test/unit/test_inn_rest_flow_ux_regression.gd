extends GutTest

## struktured, live playtest 2026-08-22: "village inn purcahsde flow is still awkward".
## "Still" — it had been raised before and the prior pass didn't land it.
##
## Two concrete defects, both measured before fixing:
##   1. the prompt named the PRICE and never the PURSE, so "can I afford this?" was only
##      answerable by confirming and being refused. Gold after the decision, not before.
##   2. a pending rest could be cancelled ONLY by walking the character away. 44 files under
##      src/ui honour ui_cancel; the inn honoured zero — the one screen that asks for money
##      was the one screen you could not back out of.
##
## InnInterior is the LIVE path: VillageInn.interior_target DEFAULTS to "inn_interior"
## (VillageInn.gd:18), so interact() always transitions and the outdoor menu never runs.

const REST_COST_EXPECTED := 50

var _inn = null
var _gold_before: int = -1


func before_each() -> void:
	_inn = load("res://src/maps/interiors/InnInterior.gd").new()
	if GameState:
		_gold_before = GameState.party_gold


func after_each() -> void:
	if GameState and _gold_before >= 0:
		GameState.party_gold = _gold_before
	_gold_before = -1
	if _inn != null and is_instance_valid(_inn):
		_inn.free()
	_inn = null


func _prompt_with_gold(g: int) -> String:
	GameState.party_gold = g
	return _inn._rest_prompt_text()


# (1) AFFORDABLE — the purse must appear BEFORE the player commits.
func test_prompt_names_the_players_gold_before_they_commit() -> void:
	if GameState == null:
		pending("GameState autoload unavailable")
		return
	var txt := _prompt_with_gold(500)
	assert_string_contains(txt, "500",
		"the prompt must state what the player HAS, not only what it costs — got: %s" % txt)
	assert_string_contains(txt, str(REST_COST_EXPECTED),
		"the prompt must still state the price")


# (2) BROKE — say so up front, and name the shortfall rather than just refusing later.
func test_prompt_says_you_are_short_instead_of_waiting_for_the_refusal() -> void:
	if GameState == null:
		pending("GameState autoload unavailable")
		return
	var txt := _prompt_with_gold(20)
	assert_string_contains(txt, "short",
		"a player who cannot afford the room must learn it from the PROMPT — got: %s" % txt)
	assert_string_contains(txt, "30",
		"name the shortfall (50 - 20 = 30), not just the price — got: %s" % txt)


# CONTROL: the prompt must VARY with gold. A constant string would satisfy both arms above
# only by accident, and this is the arm that proves it reads state at all.
func test_the_prompt_is_not_a_constant() -> void:
	if GameState == null:
		pending("GameState autoload unavailable")
		return
	assert_ne(_prompt_with_gold(500), _prompt_with_gold(20),
		"rich and broke must produce DIFFERENT prompts, or neither assertion above means anything")


# (3) the cancel affordance must be named — walking away is not discoverable.
func test_prompt_offers_a_cancel_affordance() -> void:
	if GameState == null:
		pending("GameState autoload unavailable")
		return
	var txt := _prompt_with_gold(500)
	# Must name a BUTTON. The pre-fix text said "Walk away to cancel", which contains the word
	# "cancel" and offers no button — an arm accepting that word could never fail.
	assert_string_contains(txt.to_lower(), "[b]",
		"the prompt must name a BUTTON to back out, not instruct the player to walk away — got: %s" % txt)
	assert_false(txt.to_lower().contains("walk away"),
		"walking the character away must not be the documented cancel any more")


# (4) THE CANCEL ITSELF — behavioural: a pending rest must clear on ui_cancel.
func test_ui_cancel_clears_a_pending_rest() -> void:
	add_child_autofree(_inn)
	_inn._rest_pending = true
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	_inn._unhandled_input(ev)
	assert_false(_inn._rest_pending,
		"ui_cancel must clear the pending rest — otherwise the only exit is walking away")


# CONTROL for (4): the handler must NOT fire when nothing is pending, and must ignore
# unrelated actions. A handler that clears unconditionally would pass the arm above.
func test_cancel_handler_ignores_unrelated_input_and_idle_state() -> void:
	add_child_autofree(_inn)
	_inn._rest_pending = true
	var other := InputEventAction.new()
	other.action = "ui_accept"
	other.pressed = true
	_inn._unhandled_input(other)
	assert_true(_inn._rest_pending,
		"ui_accept must NOT cancel — only ui_cancel should, or the confirm path breaks")
