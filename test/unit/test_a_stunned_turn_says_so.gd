extends GutTest

## struktured, .758 Fighter duel vs the Skeleton Knight: "fighter ... if he picked an item it just defaulted both
## players (me and the boss)". His log: Shield Bash stunned the Fighter for 3 turns, and each round after it the
## game still opened the full menu, took his pick (defer, then Hi-Potion three times) and threw it away at execution
## with no line on screen, so the round played out empty. A party member certain to lose the round is now told so
## at selection and held, and the menu never opens for a pick that cannot happen.

const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")

var _bm: Node = null
var _guard = null
var _log: Array = []


func before_each() -> void:
	_bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_log.clear()
	if _bm:
		_bm.turbo_mode = true
		_bm.is_autobattle_enabled = false
		_bm.battle_log_message.connect(_on_log)


func after_each() -> void:
	if _bm and _bm.battle_log_message.is_connected(_on_log):
		_bm.battle_log_message.disconnect(_on_log)
	if _guard != null:
		_guard.restore()


func _on_log(msg: String) -> void:
	_log.append(msg)


func _make(cname: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = cname
	c.max_hp = 400
	c.current_hp = 400
	c.attack = 10
	c.defense = 10
	c.magic = 10
	c.speed = 10
	c.is_alive = true
	add_child_autofree(c)
	return c


func _stage(pc: Combatant) -> void:
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	_bm.all_combatants.clear()
	_bm.pending_actions.clear()
	_bm.execution_order.clear()
	_bm.player_party.append(pc)
	_bm.all_combatants.append(pc)
	_bm.selection_order.clear()
	_bm.selection_order.append(pc)
	_bm.selection_index = 0
	if AutobattleSystem:
		AutobattleSystem.set_autobattle_enabled(_bm._get_character_id(pc), false)


func _logged(fragment: String) -> bool:
	for m in _log:
		if fragment in str(m):
			return true
	return false


func test_a_stunned_party_member_is_held_not_handed_a_menu() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var pc := _make("Fighter")
	pc.add_status("stun", 3)
	_stage(pc)
	watch_signals(_bm)
	assert_true(_bm._held_turn(pc), "a stunned party member's turn is held")
	assert_signal_not_emitted(_bm, "selection_turn_started", "no menu opens for a pick that cannot happen")
	var held: Array = _bm.pending_actions.filter(func(a): return a.get("combatant") == pc)
	assert_eq(held.size(), 1, "exactly one turn is queued for the stunned member")
	if held.size() == 1:
		assert_eq(str(held[0].get("type", "")), "held", "and it is a held turn, not a pick")
	assert_true(_logged("Fighter is stunned and loses this turn (3 turns left)"), "the player is told why, and for how long: %s" % str(_log))


func test_selection_skips_a_stunned_member_without_opening_its_turn() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var pc := _make("Fighter")
	pc.add_status("stun", 2)
	_stage(pc)
	var opened: Array = []
	var on_open := func(c): opened.append(c)
	_bm.selection_turn_started.connect(on_open)
	_bm.current_state = _bm.BattleState.SELECTION_PHASE
	_bm._process_next_selection()
	_bm.selection_turn_started.disconnect(on_open)
	assert_false(pc in opened, "the live selection loop never opens a stunned member's turn")
	assert_true(_logged("Fighter is stunned"), "CONTROL: the selection loop reached the stunned member: %s" % str(_log))


func test_a_member_who_can_act_still_gets_the_menu() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var pc := _make("Fighter")
	_stage(pc)
	assert_false(_bm._held_turn(pc), "no stun, no hold")
	assert_eq(_bm.pending_actions.size(), 0, "nothing is queued for a member who can act")
	pc.add_status("sleep", 2)
	assert_false(_bm._held_turn(pc), "sleep may lift at execution, so a sleeper keeps the menu")


func test_a_held_turn_whose_stun_was_cured_passes_quietly() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var pc := _make("Fighter")
	_stage(pc)
	## A foe still standing, so the battle is not already won before the held turn is reached.
	var foe := _make("Goblin")
	_bm.enemy_party.append(foe)
	_bm.all_combatants.append(foe)
	_bm.current_state = _bm.BattleState.PROCESSING_ACTION
	_bm.execution_order.append({"type": "held", "combatant": pc, "speed": 1.0})
	_bm._execute_next_action()
	assert_true(_logged("shakes it off, too late to act"), "a held turn after a cure says so rather than vanishing: %s" % str(_log))
