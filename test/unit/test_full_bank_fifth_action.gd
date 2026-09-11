extends GutTest

## FULL BANK — struktured 2026-09-10. Five party members, four AP: one member was always stranded.
##
## At +4 AP an Advance takes FIVE actions and still costs four, so one character can cover the whole
## party — Cure on all five. It fixes the stranded member and the dead fourth defer in one rule:
## before this, +3 already bought four actions, so the fourth defer bought nothing but avoiding one
## point of debt. The most patient thing a player could do was the weakest step in the economy.
##
## Design decisions this pins, so none of them can drift apart:
##   · gate on current_ap >= 4, ONE rule shared by the manual menu and autobattle scripts
##   · the fifth is FREE — refunded after execution, so a full-bank Advance nets 4 AP
##   · over-cap below a full bank TRUNCATES rather than refusing, so a 5-action script still fires
##   · enemies keep their own cap (BattleManager:2136) until it has been felt on the TV
##
## ⛔ AND THE PRESENTATION HALF WOULD HAVE SHIPPED DEAD. action_executing was emitted for attack,
## ability and the status skips — never for "advance". BattleScene's advance arm has therefore never
## fired since it was added, and the flourish would have inherited that. Pinned below.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null

func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)

func _pc(ap: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Mira"
	c.max_hp = 900; c.current_hp = 900
	c.max_mp = 200; c.current_mp = 200
	c.attack = 100; c.defense = 80; c.magic = 100; c.speed = 12
	c.job = {"id": "cleric", "abilities": ["cure"]}
	c.current_ap = ap
	return c

func _five_actions() -> Array:
	var out: Array = []
	for i in 5:
		out.append({"type": "attack", "target": null})
	return out

func test_a_full_bank_keeps_all_five() -> void:
	var c := _pc(4)
	var ruled: Dictionary = _bm._apply_full_bank_rule(c, _five_actions())
	assert_eq((ruled["actions"] as Array).size(), 5, "at +4 AP the fifth action survives")
	assert_true(bool(ruled["full_bank"]), "and it is stamped as a full bank so execution can refund it")

func test_one_short_of_a_full_bank_truncates_to_four() -> void:
	## The discriminator. +3 already bought four actions, so if the gate were wrong in this
	## direction the whole rule would be invisible — everyone would just always get five.
	var c := _pc(3)
	var ruled: Dictionary = _bm._apply_full_bank_rule(c, _five_actions())
	assert_eq((ruled["actions"] as Array).size(), 4, "at +3 the queue is still four")
	assert_false(bool(ruled["full_bank"]), "and it is not a full bank")

func test_an_over_long_queue_truncates_rather_than_fizzling() -> void:
	## A shared or imported script can author more than the cap. Refusing it outright would turn a
	## player's 5-action rule into a deferred turn at +3, which reads as the script being broken.
	var c := _pc(0)
	var ruled: Dictionary = _bm._apply_full_bank_rule(c, _five_actions())
	assert_eq((ruled["actions"] as Array).size(), 4, "trimmed to the cap")
	assert_gt((ruled["actions"] as Array).size(), 0, "and never emptied — an empty Advance stalls the battle")

func test_the_fifth_action_is_free() -> void:
	## The economy. Five executors each spend 1 AP, so without the refund a full bank would end at
	## -1 and cost the player their next turn — which is the opposite of a reward.
	var c := _pc(4)
	var target := Combatant.new()
	autofree(target)
	target.combatant_name = "Dummy"
	target.max_hp = 999999; target.current_hp = 999999
	_bm.player_party.append(c)
	_bm.enemy_party.append(target)
	var actions: Array = []
	for i in 5:
		actions.append({"type": "attack", "target": target})
	await _bm._execute_advance(c, {"type": "advance", "combatant": c, "actions": actions, "full_bank": true})
	assert_eq(c.current_ap, 0,
		"five actions from a full bank must net 4 AP spent, leaving 0 — got %d" % c.current_ap)

func test_a_four_action_advance_is_unchanged() -> void:
	## CONTROL: the existing economy must not move. Four actions from +3 still lands at -1.
	var c := _pc(3)
	var target := Combatant.new()
	autofree(target)
	target.combatant_name = "Dummy"
	target.max_hp = 999999; target.current_hp = 999999
	_bm.player_party.append(c)
	_bm.enemy_party.append(target)
	var actions: Array = []
	for i in 4:
		actions.append({"type": "attack", "target": target})
	await _bm._execute_advance(c, {"type": "advance", "combatant": c, "actions": actions, "full_bank": false})
	assert_eq(c.current_ap, -1, "four actions from +3 still ends at -1 — got %d" % c.current_ap)

func test_the_advance_announces_itself_to_the_presentation_layer() -> void:
	## ⛔ THE REACHABILITY HALF. action_executing had no "advance" emitter at all, so BattleScene's
	## advance arm — and therefore the flourish — could never run. A test that only checked the
	## flourish function would have passed against a beat nothing triggers.
	var c := _pc(4)
	var target := Combatant.new()
	autofree(target)
	target.combatant_name = "Dummy"
	target.max_hp = 999999; target.current_hp = 999999
	_bm.player_party.append(c)
	_bm.enemy_party.append(target)
	var seen: Array = []
	_bm.action_executing.connect(func(_who, act): seen.append(act))
	var actions: Array = []
	for i in 5:
		actions.append({"type": "attack", "target": target})
	await _bm._execute_advance(c, {"type": "advance", "combatant": c, "actions": actions, "full_bank": true})
	var advance_beats: Array = seen.filter(func(a): return str(a.get("type", "")) == "advance")
	assert_eq(advance_beats.size(), 1, "exactly one advance beat must reach the presentation layer")
	assert_eq((advance_beats[0]["actions"] as Array).size(), 5,
		"and it must carry the COUNT — the flourish scales its intensity on it")
	assert_true(bool(advance_beats[0]["full_bank"]),
		"and the full-bank stamp, so the scene can play the bigger beat")

func test_the_full_bank_signal_fires_once() -> void:
	var c := _pc(4)
	var target := Combatant.new()
	autofree(target)
	target.combatant_name = "Dummy"
	target.max_hp = 999999; target.current_hp = 999999
	_bm.player_party.append(c)
	_bm.enemy_party.append(target)
	var fired: Array = []
	_bm.full_bank_unleashed.connect(func(who, n): fired.append([who, n]))
	var actions: Array = []
	for i in 5:
		actions.append({"type": "attack", "target": target})
	await _bm._execute_advance(c, {"type": "advance", "combatant": c, "actions": actions, "full_bank": true})
	assert_eq(fired.size(), 1, "the flourish beat must fire exactly once, not per sub-action")
	assert_eq(int(fired[0][1]), 5, "and report the action count")
