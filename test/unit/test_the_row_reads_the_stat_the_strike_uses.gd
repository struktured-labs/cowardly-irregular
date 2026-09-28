extends GutTest

## _execute_physical_ability picks its base from `scales_with` (defense for Guard Strike, speed for
## Throw Shuriken, the caster's missing HP for Last Stand), halves it for a feared caster, and runs
## `hits` separate take_damage calls. estimate_ability_breakdown read ATK for every physical ability
## and quoted ONE hit. So a tank's Guard Strike quoted its attack stat instead of its defense, and
## Thread Slash's row showed a third of what three hits delivered, which hid [KILL] on a killing volley.
##
## The oracle is the executor itself, with volatility's variance band pinned to 1.0 so the only
## randomness left is crit, which no ability in this file authors.

class NoVariance extends VolatilitySystem:
	func get_variance_range(_c) -> Vector2:
		return Vector2(1.0, 1.0)


var _saved_vol = null


func before_each() -> void:
	_saved_vol = BattleManager.volatility
	BattleManager.volatility = NoVariance.new()


func after_each() -> void:
	BattleManager.volatility = _saved_vol


func _c(atk: int, def_v: int, spd: int, hp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Striker", "max_hp": hp, "max_mp": 99,
		"attack": atk, "defense": def_v, "magic": 10, "speed": spd})
	add_child_autofree(c)
	return c


func _dealt(caster: Combatant, target: Combatant, ability: Dictionary) -> int:
	target.current_hp = target.max_hp
	BattleManager._execute_physical_ability(caster, ability, [target])
	return target.max_hp - target.current_hp


func test_every_physical_row_quotes_what_the_strike_deals() -> void:
	## Distinct stats so the wrong one is visible: ATK 30, DEF 200, SPD 150.
	var cases: Array = [
		{"what": "CONTROL: plain ATK strike", "ability": {"id": "t_plain", "type": "physical", "damage_multiplier": 1.0}},
		{"what": "scales_with defense (guard_strike's shape)", "ability": {"id": "t_def", "type": "physical", "damage_multiplier": 1.3, "scales_with": "defense"}},
		{"what": "scales_with speed (throw_shuriken's shape)", "ability": {"id": "t_spd", "type": "physical", "damage_multiplier": 0.7, "scales_with": "speed"}},
		{"what": "scales_with missing_hp at half HP (last_stand's shape)", "ability": {"id": "t_mhp", "type": "physical", "damage_multiplier": 1.0, "scales_with": "missing_hp", "max_multiplier": 5.0}, "half_hp": true},
		{"what": "three hits (thread_slash's shape)", "ability": {"id": "t_hits", "type": "physical", "damage_multiplier": 0.8, "hits": 3}},
		{"what": "a feared caster", "ability": {"id": "t_fear", "type": "physical", "damage_multiplier": 1.0}, "fear": true},
	]
	var wrong: Array[String] = []
	var control_ok := false
	for row in cases:
		var caster := _c(30, 200, 150, 1000)
		var target := _c(10, 20, 1, 100000000)
		if row.get("half_hp", false):
			caster.current_hp = 500
		if row.get("fear", false):
			caster.add_status("fear", 99)
		var quoted: int = int(BattleManager.estimate_ability_breakdown(caster, target, row["ability"])["damage"])
		var dealt: int = _dealt(caster, target, row["ability"])
		if quoted == dealt:
			control_ok = control_ok or str(row["what"]).begins_with("CONTROL")
		else:
			wrong.append("%s: the row reads ~%d, the strike deals %d" % [row["what"], quoted, dealt])
	assert_true(control_ok,
		"CONTROL: a plain ATK strike must already match the executor, or the oracle is off: %s" % str(wrong))
	assert_eq(wrong, [],
		"a physical ability's ~N dmg row must equal what _execute_physical_ability deals: %s" % str(wrong))
