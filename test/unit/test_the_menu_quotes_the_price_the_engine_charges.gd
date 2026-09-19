extends GutTest

## A Mage with `mp_efficiency` ("-25% MP costs") saw a 20-MP spell greyed out at 18 MP, while the
## engine would have charged 15 and let it fire. With `magic_amplifier` ("+150% MP costs") the same
## menu offered a spell at its authored price and the engine wanted 2.5x that.
##
## `JobSystem.get_ability_mp_cost` is the canonical resolver and applies the passive
## `mp_cost_multiplier`. Tick 374 routed `can_use_ability` and `BattleManager._execute_ability`
## through it — and `BattleCommandMenu._build_ability_menu_item` kept reading the raw
## `ability.get("mp_cost", 0)`, which is the number a player is SHOWN, gated on, and greyed out by.
##
## ⛔ THE EXISTING GUARD FOR THIS EXACT BUG CLASS IS GREEN AND ALWAYS WAS:
## `test_passive_mp_cost_multiplier_wired_regression` pins the resolver's existence and pins that
## JobSystem and BattleManager call it. Its corpus is those two files. The menu was never in it —
## the sibling the original fix did not reach.
##
## Arms derive the multiplier from PassiveSystem rather than hardcoding 0.75, so a new passive
## carrying `mp_cost_multiplier` is covered the day it is authored.

const MENU_SCRIPT := "res://src/battle/BattleCommandMenu.gd"

var _js: Node = null
var _ps: Node = null


func before_each() -> void:
	_js = get_node_or_null("/root/JobSystem")
	_ps = get_node_or_null("/root/PassiveSystem")


## Costly enough that a 0.75x multiplier moves the rounded int, and routed to the menu's FLAT
## branch. The single_enemy/ally/dead_ally/all_* branches read `_scene`, so without a live
## BattleScene they abort mid-function and yield Dictionary's default {} — a silent empty item
## rather than an error, which is the same abort-and-return-the-default GDScript behaviour
## CLAUDE.md documents. Picking a flat-branch ability keeps this file measuring the price.
const SCENE_BRANCHES := ["single_enemy", "single_ally", "dead_ally", "all_enemies", "all_allies"]


func _costly_ability() -> String:
	if _js == null:
		return ""
	for aid in _js.abilities:
		var ab: Dictionary = _js.abilities[aid]
		if int(ab.get("mp_cost", 0)) < 8:
			continue
		if str(ab.get("target_type", "single_enemy")) in SCENE_BRANCHES:
			continue
		return str(aid)
	return ""


## Passives that actually move MP cost, read from PassiveSystem so a new one is picked up.
func _cost_passives() -> Array[String]:
	var out: Array[String] = []
	if _ps == null or not ("passives" in _ps):
		return out
	for pid in _ps.passives:
		var mods: Dictionary = (_ps.passives[pid] as Dictionary).get("stat_mods", {})
		if not mods.has("mp_cost_multiplier"):
			continue
		if not is_equal_approx(float(mods["mp_cost_multiplier"]), 1.0):
			out.append(str(pid))
	return out


func _caster(mp: int, passives: Array[String]) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Quoted", "max_hp": 200, "max_mp": 999,
		"attack": 10, "defense": 10, "magic": 40, "speed": 10})
	add_child_autofree(c)
	c.current_mp = mp
	c.equipped_passives = passives.duplicate()
	return c


func _menu_item(c: Combatant, ability_id: String) -> Dictionary:
	## _init(scene) takes a required arg and only assigns it; the flat branch never reads it.
	var menu = load(MENU_SCRIPT).new(null)
	var foes: Array[Combatant] = []
	var foe := Combatant.new()
	foe.initialize({"name": "Target", "max_hp": 500, "max_mp": 0,
		"attack": 1, "defense": 1, "magic": 1, "speed": 1})
	add_child_autofree(foe)
	foes.append(foe)
	return menu._build_ability_menu_item(ability_id, c, foes, Transform2D.IDENTITY)


func test_a_cost_moving_passive_exists_to_measure_with() -> void:
	assert_not_null(_js, "CONTROL: JobSystem must resolve or every arm here is vacuous")
	assert_not_null(_ps, "CONTROL: PassiveSystem must resolve or every arm here is vacuous")
	assert_gt(_cost_passives().size(), 0,
		"CONTROL: at least one passive must carry a non-1.0 mp_cost_multiplier, or the arms below "
		+ "compare a number against itself and pass whatever the menu reads")
	assert_ne(_costly_ability(), "",
		"CONTROL: an ability with mp_cost >= 8 must exist, or rounding can hide the multiplier")


func test_the_menu_quotes_what_the_engine_would_charge() -> void:
	var aid := _costly_ability()
	if aid == "" or _cost_passives().is_empty():
		pending("needs JobSystem/PassiveSystem and a costly ability; the control arm reports why")
		return
	var wrong: Array[String] = []
	for pid in _cost_passives():
		var c := _caster(999, [pid] as Array[String])
		var engine_cost: int = int(_js.get_ability_mp_cost(c, aid))
		var quoted: int = int(_menu_item(c, aid).get("cost", -1))
		if quoted != engine_cost:
			wrong.append("%s: menu quotes %d, engine charges %d" % [pid, quoted, engine_cost])
	assert_eq(wrong, [],
		"the menu's `cost` is what a player is shown and gated on; it must equal "
		+ "JobSystem.get_ability_mp_cost, which is what _execute_ability spends: %s" % str(wrong))


func test_a_discount_is_not_greyed_out_at_the_undiscounted_price() -> void:
	var aid := _costly_ability()
	if aid == "" or _js == null:
		pending("needs JobSystem and a costly ability; the control arm reports why")
		return
	## A passive that makes the ability CHEAPER, so a wallet between the two prices exists.
	var discount := ""
	for pid in _cost_passives():
		var probe := _caster(999, [pid] as Array[String])
		if int(_js.get_ability_mp_cost(probe, aid)) < int((_js.abilities[aid] as Dictionary).get("mp_cost", 0)):
			discount = pid
			break
	if discount == "":
		pending("no cost-REDUCING passive authored; the raise-only case is covered by the arm above")
		return
	var base: int = int((_js.abilities[aid] as Dictionary).get("mp_cost", 0))
	var probe2 := _caster(999, [discount] as Array[String])
	var reduced: int = int(_js.get_ability_mp_cost(probe2, aid))
	## Strictly between the two prices: the engine can afford it, the raw number says it cannot.
	var wallet: int = reduced + int(floor(float(base - reduced) / 2.0))
	assert_lt(wallet, base, "CONTROL: the wallet must be BELOW the authored price or this proves nothing")
	assert_true(wallet >= reduced, "CONTROL: the wallet must cover the discounted price")
	var c := _caster(wallet, [discount] as Array[String])
	var item := _menu_item(c, aid)
	assert_false(bool(item.get("disabled", false)),
		"with %s the engine charges %d and the player holds %d, so the row must be selectable — "
		% [discount, reduced, wallet] + "greying it out at the authored %d is the discount the "
		% base + "passive promised being invisible in the one place the player reads it")
