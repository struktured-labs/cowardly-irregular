extends GutTest

## The player opened a conversation and every option on the menu ended it.
##
## `validate_player_choices` answers "nothing usable" with the authored fallback
## set — three times over: a non-Dictionary reply, a non-Array `choices`, and an
## empty survivor list. A menu of nothing but goodbyes is that same state one step
## later, and it was returned as a valid menu.
##
## ⛔ IT BECAME REACHABLE WHEN MY OWN DEDUPE LANDED. Measured on the real validator:
##
##     ["Farewell.", "Farewell.", "Farewell."]   -> ["Farewell."]
##     ["Goodbye.", "Goodbye.", "Farewell."]     -> ["Goodbye.", "Farewell."]   fine
##     ["Tell me more." x3]                      -> ["Tell me more."]           fine
##
## One survivor, and it is an exit. `_ensure_farewell` then returns early — a
## farewell already exists — so the player is handed a ONE-OPTION menu whose only
## option leaves. They cannot say anything; they can only go.
##
## 🔑 THE FAILURE IS NON-MONOTONIC, which is why nothing upstream caught it: a
## PARTIALLY usable reply produced a worse menu than a COMPLETELY unusable one.
## Every guard on this path asks "did we get something?" and the answer was yes.
##
## Not observed with llama3 (18 of 18 return three distinct, non-exit choices).
## This defends the BYOK surface — any OpenAI-compatible model can be attached
## from Settings, and a terse one repeating "Goodbye." is exactly the shape.
##
## ⚠️ Farewell POSITION is deliberately untouched and stays the parked design
## question. `_ensure_farewell` runs immediately after this and owns where the
## exit sits; this only guarantees there is something else on the menu.

const DP := preload("res://src/llm/DialoguePrompts.gd")

var _dc: DynamicConversation


func before_each() -> void:
	_dc = DynamicConversation.new()
	_dc.name = "MenuGuardConversation"
	add_child_autofree(_dc)


func _after_both_passes(initial: Array[String]) -> Array[String]:
	## The real pair, in the real order, as _run_exchange calls them.
	var choices: Array[String] = initial.duplicate()
	_dc._ensure_something_to_say(choices)
	_dc._ensure_farewell(choices)
	return choices


func _non_exit_count(choices: Array[String]) -> int:
	var n: int = 0
	for c in choices:
		if not _dc._is_farewell(c):
			n += 1
	return n


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_lone_farewell_is_not_the_whole_menu() -> void:
	## THE ARM — exactly what the dedupe leaves for three identical goodbyes.
	var out: Array[String] = _after_both_passes(["Farewell."] as Array[String])
	assert_gt(_non_exit_count(out), 0,
		("every option on the menu ends the conversation: %s. The player has nothing they can "
		+ "say. Fix in DynamicConversation._ensure_something_to_say — top up from "
		+ "DialoguePrompts.FALLBACK_PLAYER_CHOICES, which is what validate_player_choices "
		+ "already returns when a reply is unusable at all.") % str(out))


func test_the_dedupe_really_produces_that_input() -> void:
	## THE PREMISE, driven through the real validator rather than assumed. If the
	## dedupe stops collapsing identical goodbyes, this arm's subject is gone and
	## the repair should be re-read rather than kept on faith.
	var v: Dictionary = DP.validate_player_choices(
		{"choices": ["Farewell.", "Farewell.", "Farewell."]}, 3)
	var got: Array = v.get("choices", []) as Array
	assert_eq(got.size(), 1, "three identical goodbyes must collapse to one: %s" % str(got))
	assert_true(_dc._is_farewell(str(got[0])), "and the survivor must be an exit: %s" % str(got))


func test_every_exit_shape_the_predicate_knows_is_covered() -> void:
	## Not just the literal "Farewell." — the predicate recognises several, and a
	## model repeating any of them reaches the same dead end.
	var bad: Array[String] = []
	for shape in ["Farewell.", "Goodbye.", "Take care.", "I should go."]:
		var out: Array[String] = _after_both_passes([shape] as Array[String])
		if _non_exit_count(out) == 0:
			bad.append(shape)
	assert_eq(bad, ([] as Array[String]),
		"these leave a menu of pure exits: %s" % ", ".join(bad))


func test_two_exits_and_nothing_else_is_also_repaired() -> void:
	## The dedupe does not have to collapse to ONE for the menu to be all exits.
	var out: Array[String] = _after_both_passes(["Goodbye.", "Farewell."] as Array[String])
	assert_gt(_non_exit_count(out), 0, "two exits are still no menu: %s" % str(out))


# ── it must not disturb a usable menu ─────────────────────────────────────────

func test_a_normal_menu_is_untouched() -> void:
	## CORRECT-WORK. The repair must fire only on the degenerate case; rewriting a
	## working menu would discard what the model actually wrote.
	var given: Array[String] = ["What happened here?", "Who is the Chancellor?", "Farewell."]
	var out: Array[String] = _after_both_passes(given)
	assert_eq(out, given, "a menu with real options must pass through unchanged")


func test_a_single_real_option_is_kept() -> void:
	## Under-delivery is a recorded gap, not this one's business: one usable choice
	## is a thin menu, not a dead end, and the exit gets appended as always.
	var out: Array[String] = _after_both_passes(["Tell me more."] as Array[String])
	assert_true(out.has("Tell me more."), "the model's one real option must survive: %s" % str(out))
	assert_gt(_non_exit_count(out), 0, "and it must still be sayable")


func test_the_repair_still_leaves_a_way_out() -> void:
	## CONTROL: replacing a pure-exit menu must not remove the exit. The player
	## must always be able to end the conversation.
	for shape in ["Farewell.", "Goodbye."]:
		var out: Array[String] = _after_both_passes([shape] as Array[String])
		var exits: int = out.size() - _non_exit_count(out)
		assert_gt(exits, 0, "'%s' left no way to leave: %s" % [shape, str(out)])


func test_the_repair_is_actually_called_before_the_farewell_pass() -> void:
	## EXECUTION IS NOT SELECTION. Every arm above calls the helper directly, so
	## deleting its call site would leave them green while no real menu was ever
	## repaired — and it must run BEFORE _ensure_farewell, which returns early on
	## a menu that already contains an exit and would mask the whole defect.
	var src: String = _code_only(FileAccess.get_file_as_string("res://src/llm/DynamicConversation.gd"))
	assert_false(src.is_empty(), "CONTROL: source must load")
	var repair_at: int = src.find("_ensure_something_to_say(choices)")
	var farewell_at: int = src.find("_ensure_farewell(choices)")
	assert_true(repair_at != -1, "_run_exchange must call _ensure_something_to_say on the menu")
	assert_true(farewell_at != -1, "CONTROL: the farewell pass must still be called")
	assert_true(repair_at < farewell_at,
		"the repair must run BEFORE _ensure_farewell — that one returns early when an exit "
		+ "is already present, which is exactly the degenerate menu this fixes")


func test_the_menu_never_exceeds_the_maximum() -> void:
	## CONTROL: the top-up plus the appended farewell must stay inside the panel's
	## capacity, or the repair trades a dead end for a clipped menu.
	for given in [["Farewell."], ["Goodbye.", "Farewell."], ["Tell me more."]]:
		var typed: Array[String] = []
		for s in given:
			typed.append(str(s))
		var out: Array[String] = _after_both_passes(typed)
		assert_lte(out.size(), DP.MAX_CHOICES,
			"a repaired menu must fit MAX_CHOICES (%d): %s" % [DP.MAX_CHOICES, str(out)])


func _code_only(src: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		if line.find("\"\"\"") != -1:
			continue
		var hash_at: int = line.find("#")
		out.append(line if hash_at == -1 else line.substr(0, hash_at))
	return "\n".join(out)
