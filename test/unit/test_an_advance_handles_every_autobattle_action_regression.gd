extends GutTest

## AutobattleSystem.ACTION_TYPES has FOUR members — attack, ability, item, defer — and the Advance
## executor's match had three. So a rule built in the shipped editor as [attack, defer] attacked and
## then silently did nothing: push_warning to the godot log, no defensive stance, no AP retention,
## and no line the player could see. _convert_autobattle_action:8779 returns {"type":"defer"} and
## the conversion packs it straight into advance_actions, grammar validation has no positional rule
## (it checks only ACTION_TYPES membership), and the editor's "gray out remaining slots" is a BREAK
## in the RENDER loop, so the data happily holds a defer in slot 2.
## Derived, not hand-listed: a fifth action type reds this arm instead of being skipped in battle.

const AutobattleScript = preload("res://src/autobattle/AutobattleSystem.gd")


func _advance_match_block() -> String:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var fn := src.find("func _execute_advance(")
	assert_gt(fn, -1, "CONTROL: _execute_advance was found")
	if fn < 0:
		return ""
	var next := src.find("\nfunc ", fn + 1)
	return src.substr(fn, next - fn)


func test_every_autobattle_action_type_has_an_advance_arm() -> void:
	var types: Dictionary = AutobattleScript.ACTION_TYPES
	assert_gt(types.size(), 0, "CONTROL: the vocabulary resolved")
	var body := _advance_match_block()
	assert_gt(body.length(), 200, "CONTROL: the executor body was extracted")
	for atype in types.keys():
		assert_true(body.contains('"%s":' % str(atype)),
			"Advance must handle the '%s' action the editor can queue — an unhandled type is " % str(atype) +
			"skipped with only a push_warning, which no player sees")


func test_a_queued_defer_ends_the_queue() -> void:
	## The editor grays out the slots after a defer; that must be a rule the engine keeps, not a
	## drawing choice. Without it, actions queued behind a defer would run after the turn was given up.
	var body := _advance_match_block()
	var defer_idx := body.find('"defer":')
	assert_gt(defer_idx, -1, "the defer arm exists")
	var tail := body.substr(defer_idx, 220)
	assert_true(tail.contains("queue_ended"),
		"a queued defer must end the queue — 'defer blocks the remaining slots' is the documented rule")


func test_the_bookkeeping_is_not_duplicated_inside_the_arms() -> void:
	## Each executed action logs once, emits once and counts once. The first version of the defer
	## arm broke out of the loop and so had to repeat all three inline — a replicated rule invites
	## the next arm to forget one. One site, reached by every arm.
	var body := _advance_match_block()
	assert_eq(body.count("_log_player_action(combatant, action)"), 1,
		"one _log_player_action site for the whole loop")
	assert_eq(body.count("executed += 1"), 1, "one executed counter site")
