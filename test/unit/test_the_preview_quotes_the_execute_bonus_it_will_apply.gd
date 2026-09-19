extends GutTest

## The Arbiter Lens's passive is called Final Word and reads "Deal +50% damage to enemies below 25%
## HP". `_apply_lens_execute_bonus` applies it on ALL THREE damage paths — basic attack (:4490),
## physical ability (:4926), magic ability (:5272) — and the estimators applied it on none.
##
## ⛔ SO THE PREVIEW WAS BLIND EXACTLY WHERE THE PASSIVE LIVES. BattleCommandMenu renders `[KILL]`
## when `est >= current_hp`, and the bonus fires only on a target already below a quarter HP — the
## one moment a player is reading that tag to decide whether this finishes it. A lens whose entire
## text is about finishing the wounded was invisible in the one place the player asks.
##
## ⛔ AND THE PREVIEW COULD NOT SIMPLY CALL `_apply_lens_execute_bonus`: it EMITS
## `battle_log_message` ("X moves to finish it"), and the menu builds a row per enemy per ability —
## so reusing it would have written the battle log from a menu redraw. The multiplier is factored
## into `lens_execute_multiplier`, which both the quote and the charge read; the emit stays with the
## executor. The last arm pins that, because it is the reason the shape is what it is.
##
## Arms derive the threshold and bonus from LensSystem rather than hardcoding 0.25/0.5, so a
## rebalance of the lens moves the test with it.

const BM_SRC := "res://src/battle/BattleManager.gd"

var _saved_assignments: Dictionary = {}


func before_each() -> void:
	if GameState != null and "lens_assignments" in GameState:
		_saved_assignments = GameState.lens_assignments.duplicate(true)


func after_each() -> void:
	if GameState != null and "lens_assignments" in GameState:
		GameState.lens_assignments.clear()
		for k in _saved_assignments:
			GameState.lens_assignments[k] = _saved_assignments[k]


func _bm() -> Node:
	var bm: Node = load(BM_SRC).new()
	add_child_autofree(bm)
	return bm


func _pc() -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = "Executioner"
	c.is_alive = true
	c.max_hp = 500
	c.current_hp = 500
	c.attack = 200
	c.magic = 200
	return c


## hp_fraction of max, so a target can be placed either side of the lens threshold.
func _target(hp_fraction: float) -> Combatant:
	var t: Combatant = autofree(Combatant.new())
	t.combatant_name = "Wounded"
	t.is_alive = true
	t.max_hp = 1000
	t.current_hp = maxi(1, int(1000.0 * hp_fraction))
	t.defense = 40
	t.magic_defense = 40
	return t


## The axis that authors the execute keys, found rather than named.
func _execute_axis() -> String:
	if LensSystem == null or not ("lenses" in LensSystem):
		return ""
	for axis in LensSystem.lenses:
		var me: Dictionary = (LensSystem.lenses[axis] as Dictionary).get("meta_effects", {})
		if float(me.get("lens_execute_threshold", 0.0)) > 0.0 and float(me.get("lens_execute_bonus", 0.0)) > 0.0:
			return str(axis)
	return ""


func _equip(c: Combatant, axis: String) -> void:
	GameState.lens_assignments[c.combatant_name.to_lower().replace(" ", "_")] = axis


func _threshold(axis: String) -> float:
	return float((LensSystem.lenses[axis] as Dictionary).get("meta_effects", {}).get("lens_execute_threshold", 0.0))


func test_a_lens_authoring_an_execute_bonus_exists_to_measure_with() -> void:
	assert_not_null(LensSystem, "CONTROL: LensSystem must resolve or every arm here is vacuous")
	assert_not_null(GameState, "CONTROL: GameState holds lens_assignments; without it nothing equips")
	var axis := _execute_axis()
	assert_ne(axis, "",
		"CONTROL: some lens must author lens_execute_threshold AND lens_execute_bonus, or the arms "
		+ "below compare a number against itself")
	assert_gt(_threshold(axis), 0.0, "CONTROL: the threshold must be a real HP fraction")


func test_a_wounded_target_previews_the_bonus_the_swing_will_add() -> void:
	var axis := _execute_axis()
	if axis == "":
		pending("no execute lens authored; the control arm reports why")
		return
	var bm := _bm()
	var below := _threshold(axis) / 2.0
	var bare: int = int(bm.estimate_attack_damage(_pc(), _target(below)))
	var caster := _pc()
	_equip(caster, axis)
	var lensed: int = int(bm.estimate_attack_damage(caster, _target(below)))
	assert_gt(bare, 0, "CONTROL: the unlensed preview must be non-zero for the comparison to hold")
	assert_gt(lensed, bare,
		"the lens adds damage to a target below the threshold and the engine applies it on every "
		+ "damage path, so the menu must quote MORE (bare %d, lensed %d)" % [bare, lensed])


func test_an_ability_preview_carries_it_too() -> void:
	var axis := _execute_axis()
	if axis == "":
		pending("no execute lens authored; the control arm reports why")
		return
	var bm := _bm()
	var ability := {"type": "magic", "damage_multiplier": 2.0}
	var below := _threshold(axis) / 2.0
	var bare: int = int(bm.estimate_ability_damage(_pc(), _target(below), ability))
	var caster := _pc()
	_equip(caster, axis)
	var lensed: int = int(bm.estimate_ability_damage(caster, _target(below), ability))
	assert_gt(lensed, bare,
		"_apply_lens_execute_bonus runs on the ability paths as well as the basic attack, so the "
		+ "ability row must quote the bonus too (bare %d, lensed %d)" % [bare, lensed])


func test_a_healthy_target_previews_no_bonus_at_all() -> void:
	## The discriminator: without this, "the lens always adds" passes the two arms above.
	var axis := _execute_axis()
	if axis == "":
		pending("no execute lens authored; the control arm reports why")
		return
	var bm := _bm()
	var healthy := minf(1.0, _threshold(axis) + 0.5)
	var bare: int = int(bm.estimate_attack_damage(_pc(), _target(healthy)))
	var caster := _pc()
	_equip(caster, axis)
	var lensed: int = int(bm.estimate_attack_damage(caster, _target(healthy)))
	assert_eq(lensed, bare,
		"the bonus is gated on the target being BELOW the threshold — quoting it on a healthy "
		+ "enemy would advertise damage the swing will not deal (bare %d, lensed %d)" % [bare, lensed])


func test_building_a_preview_writes_nothing_to_the_battle_log() -> void:
	## Why `lens_execute_multiplier` exists apart from `_apply_lens_execute_bonus`: the menu builds a
	## row per enemy per ability, and the executor's version emits "X moves to finish it".
	var axis := _execute_axis()
	if axis == "":
		pending("no execute lens authored; the control arm reports why")
		return
	var bm := _bm()
	var caster := _pc()
	_equip(caster, axis)
	var lines: Array[String] = []
	bm.battle_log_message.connect(func(msg: String) -> void: lines.append(msg))
	var below := _threshold(axis) / 2.0
	var previewed: int = int(bm.estimate_attack_damage(caster, _target(below)))
	assert_gt(previewed, 0, "CONTROL: the preview must have run, or an empty log proves nothing")
	assert_eq(lines, [] as Array[String],
		"a preview must not write the battle log — the menu redraws one row per enemy per ability, "
		+ "so reusing the emitting helper would spam it: %s" % str(lines))
