extends GutTest

## ⛔ REPEAT SUBSTITUTES A BASIC ATTACK IN THREE CASES, AND SAID SO ONLY TO THE LOG FILE. The
## command ADVERTISES last round's plan (hint bar, Y / west face). Three per-member fallbacks hand
## the member a plain swing instead:
##
##   no stored action at all      a member KO'd last round queued nothing, so
##                                _save_previous_actions stored nothing for them
##   saved Advance unaffordable    "Fire x3" repeated with no MP left
##   saved ability/item unaffordable
##
## The substitution is RIGHT — its own comment says an unaffordable cast would otherwise fail at
## execution and spend the turn on nothing. What was wrong is that each site carried a print() and
## nothing else, and print reaches the log FILE, never the battle log panel. The player pressed
## Repeat expecting their plan, watched a swing, and was told nothing.
##
## The WHOLE-PARTY case is refused earlier with a reason the player does see
## (last_repeat_refusal -> BattleScene:876), which is why these three went unnoticed: the loud path
## was already covered and these are the quiet ones beside it.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")

var _battle_state: RefCounted = null
var _lines: Array[String] = []


func before_each() -> void:
	_battle_state = BattleStateHelper.new()
	_battle_state.snapshot()
	_lines.clear()
	## A NAMED method, never a bare lambda. Nothing holds a lambda's Callable, so it cannot be
	## disconnected, and a connection left on an AUTOLOAD signal outlives this file — the leak
	## class that got another of my branches dropped from .691.
	if not BattleManager.battle_log_message.is_connected(_on_log):
		BattleManager.battle_log_message.connect(_on_log)


func after_each() -> void:
	## FIRST, above anything that can abort: an error below would strand the connection.
	if BattleManager.battle_log_message.is_connected(_on_log):
		BattleManager.battle_log_message.disconnect(_on_log)
	if _battle_state != null:
		_battle_state.restore()


func _on_log(message: String) -> void:
	_lines.append(message)


func _pc(pname: String, mp: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = pname
	c.job = {"id": "mage", "abilities": ["fire"]}
	c.max_hp = 200
	c.current_hp = 200
	c.max_mp = 99
	c.current_mp = mp
	c.is_alive = true
	return c


## One player, one live foe, and whatever this round remembers. Established rather than only
## snapshotted, so an earlier file's leftovers cannot decide the answer.
func _stage(member: Combatant, remembered: Array) -> void:
	var foe := _pc("Goblin", 0)
	BattleManager.player_party.assign([member])
	BattleManager.enemy_party.assign([foe])
	BattleManager.pending_actions.clear()
	BattleManager.previous_round_actions.clear()
	if not remembered.is_empty():
		BattleManager.previous_round_actions[member.combatant_name.to_lower()] = remembered


## Did the player get told, for THIS member? The detector is the member's NAME alone, deliberately.
##
## ⚠️ IT USED TO ALSO REQUIRE THE PHRASE "attacking instead", WHICH PINS MY OWN CAPTION: a
## reworded message would red three arms for a cosmetic change, and a guard you cannot reword is a
## guard that forbids improving the thing it defends. What is load-bearing is that the player is told
## AND that the CAUSE is distinguishable — so the cause keywords stay asserted per arm ("repeat",
## "afford", "advance") and the detector itself claims nothing about wording.
##
## Safe because this fixture drives one combatant through one call and nothing else emits: the
## control arm's "no line names this member" is a real absence, not a filtered one.
func _told_about(member: Combatant) -> String:
	for line in _lines:
		if member.combatant_name in line:
			return line
	return ""


func test_the_symbols_this_file_drives_exist() -> void:
	assert_true(BattleManager.has_method("_queue_repeated_action"),
		"FLOOR: _queue_repeated_action is the function that substitutes")
	assert_true(BattleManager.has_method("_announce_repeat_substitution"),
		"FLOOR: the announcement is the fix; a rename must red here by name")
	assert_true(BattleManager.has_signal("battle_log_message"),
		"FLOOR: the battle log panel is the surface a print() cannot reach")
	assert_true("previous_round_actions" in BattleManager,
		"FLOOR: what Repeat reads")


## CASE 1 — nothing stored for this member at all (KO'd last round, revived this one).
func test_a_member_with_nothing_stored_is_told_it_swung_instead() -> void:
	var pc := _pc("Cleric", 99)
	_stage(pc, [])
	BattleManager.previous_round_actions["someone_else"] = [{"type": "attack"}]
	BattleManager._queue_repeated_action(pc)
	var said: String = _told_about(pc)
	gut.p("case 1 said: '%s'" % said)
	assert_ne(said, "",
		("a member with nothing to repeat got a basic attack and the player was told only in the "
		+ "log FILE. Lines seen: %s") % str(_lines))
	assert_true("repeat" in said.to_lower(),
		"and the reason must name the cause, not just the swing: '%s'" % said)
	assert_eq(BattleManager.pending_actions.size(), 1,
		"CONTROL: the substitution still happens — telling the player must not replace it")
	assert_eq(str(BattleManager.pending_actions[0].get("type", "")), "attack",
		"CONTROL: and what it queues is still a basic attack")


## CASE 2 — a single saved cast that today's MP cannot pay for.
func test_an_unaffordable_saved_cast_is_told() -> void:
	var pc := _pc("Mage", 0)
	_stage(pc, [{"type": "ability", "ability_id": "fire"}])
	BattleManager._queue_repeated_action(pc)
	var said: String = _told_about(pc)
	gut.p("case 2 said: '%s'" % said)
	assert_ne(said, "",
		("a saved cast the party can no longer afford became a swing in silence. Repeat promises "
		+ "last round's plan, so the swap is exactly what needs saying. Lines: %s") % str(_lines))
	assert_true("afford" in said.to_lower(),
		"and affordability is a different cause from 'nothing to repeat': '%s'" % said)


## CASE 3 — a saved ADVANCE whose every step is unaffordable now.
func test_an_unaffordable_saved_advance_is_told() -> void:
	var pc := _pc("Mage", 0)
	_stage(pc, [{"type": "advance", "actions": [{"type": "ability", "ability_id": "fire"}]}])
	BattleManager._queue_repeated_action(pc)
	var said: String = _told_about(pc)
	gut.p("case 3 said: '%s'" % said)
	assert_ne(said, "",
		("a repeated Advance with nothing affordable left became one swing, silently — the case a "
		+ "player meets by repeating 'Fire x3' with an empty pool. Lines: %s") % str(_lines))
	assert_true("advance" in said.to_lower(),
		"and it must name the Advance rather than read as a single cast: '%s'" % said)


## ⛔ THE CONTROL, and the arms above are worth nothing without it: a repeat that GOES THROUGH must
## say nothing at all. An implementation that announced unconditionally would satisfy all three
## cases above while narrating a substitution that never happened, every single turn.
func test_a_repeat_that_goes_through_says_nothing() -> void:
	var pc := _pc("Mage", 99)
	_stage(pc, [{"type": "ability", "ability_id": "fire"}])
	BattleManager._queue_repeated_action(pc)
	## ⛔ AN ABSENCE HAS NO LOUD DIRECTION OF ITS OWN: if _queue_repeated_action aborted, nothing
	## emits and this assert PASSES vacuously. The two asserts below it are the canary — they red
	## when nothing ran, which is what separates "it stayed quiet" from "it never executed".
	assert_eq(_told_about(pc), "",
		("CONTROL: an affordable saved cast was repeated as asked, so there is no substitution to "
		+ "announce. Got: %s") % str(_lines))
	assert_eq(BattleManager.pending_actions.size(), 1, "CONTROL: it queued exactly one action")
	assert_eq(str(BattleManager.pending_actions[0].get("type", "")), "ability",
		("CONTROL: and it queued the SAVED CAST, not a swing — otherwise this arm passes while "
		+ "every repeat silently degrades"))
