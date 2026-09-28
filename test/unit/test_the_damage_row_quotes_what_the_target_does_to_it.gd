extends GutTest

## The "~N dmg" row and its [KILL] tag came from BattleManager.estimate_*_breakdown, which stopped at
## the defense formula. Combatant.take_damage then went on to apply the TARGET's side of the hit:
## a vulnerability debuff before defense, a defending target (x0.5), `exposed` (x1.5) and the
## Scriptweaver damage_multiplier dial. So against a guarding boss the row claimed twice what landed,
## and against an exposed foe (the state a group attack leaves them in, which is exactly when the
## finishing blow is lined up) it undercounted by a third, and [KILL] stayed dark on a hit that killed.
##
## The oracle is take_damage itself, fed the preview's own pre-defense amount. For a basic attack
## with no lens that amount is the attacker's buffed ATK, so the row and the engine agree only if
## the preview runs the target's modifiers too.

const DIAL := "damage_multiplier"

var _saved_dial: float = 1.0


func before_each() -> void:
	_saved_dial = float(GameState.game_constants.get(DIAL, 1.0))


func after_each() -> void:
	GameState.game_constants[DIAL] = _saved_dial


func _c(atk: int, def_v: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Foe", "max_hp": 100000000, "max_mp": 0,
		"attack": atk, "defense": def_v, "magic": 10, "speed": 10})
	## In the tree: take_damage reads the dial through get_tree().
	add_child_autofree(c)
	return c


## What take_damage actually removes for this incoming amount, on a fresh full-HP copy of the state.
func _landed(target: Combatant, incoming: int) -> int:
	target.current_hp = target.max_hp
	var before: int = target.current_hp
	target.take_damage(incoming, false)
	return before - target.current_hp


func test_every_target_side_factor_reaches_the_quote() -> void:
	var attacker := _c(120, 10)
	var target := _c(10, 40)
	var rows: Array = [
		{"what": "no factor (CONTROL)", "defend": false, "exposed": false, "dial": 1.0},
		{"what": "a defending target", "defend": true, "exposed": false, "dial": 1.0},
		{"what": "an exposed target", "defend": false, "exposed": true, "dial": 1.0},
		{"what": "the damage dial at 2.0", "defend": false, "exposed": false, "dial": 2.0},
		{"what": "defending AND exposed", "defend": true, "exposed": true, "dial": 1.0},
	]
	var wrong: Array[String] = []
	var control_agreed := false
	for row in rows:
		GameState.game_constants[DIAL] = float(row["dial"])
		target.is_defending = bool(row["defend"])
		target.remove_status("exposed")
		if bool(row["exposed"]):
			target.add_status("exposed", 99)
		var quoted: int = int(BattleManager.estimate_attack_breakdown(attacker, target)["damage"])
		var incoming: int = attacker.get_buffed_stat("attack", attacker.attack)
		var landed: int = _landed(target, incoming)
		if quoted == landed:
			if str(row["what"]).begins_with("no factor"):
				control_agreed = true
		else:
			wrong.append("%s: the row reads ~%d, the hit removes %d" % [row["what"], quoted, landed])
	target.is_defending = false
	target.remove_status("exposed")
	assert_true(control_agreed,
		"CONTROL: with every factor at identity the quote must already equal the hit, or the oracle "
		+ "is measuring something else: %s" % str(wrong))
	assert_eq(wrong, [],
		"the ~N dmg row (and its [KILL] tag) must equal what take_damage removes. Factors the "
		+ "quote is blind to: %s" % str(wrong))
