extends GutTest

## `_execute_magic_ability` scales elemental damage by terrain × weather (BattleManager.gd:5278),
## and the battle-log caption beside it reported `terrain_mod` ALONE, labelled "(terrain ±N%)".
##
## Weather v2 landed 2026-09-04 on a line that already carried a terrain caption, and the caption was
## never widened — so the log understated a rain-in-a-cave reduction by half, and said NOTHING at all
## for a storm's +25% on plains, where terrain is the identity and weather is the whole effect.
##
## ⛔ THAT CAPTION IS THE ONLY IN-LOG EXPLANATION OF WHY THE NUMBER MOVED. A player watching Fire land
## for 44% less in a cave during rain was told "terrain -25%" and left to account for the rest.
##
## Arms derive the expected figure from the engine's own two resolvers rather than hardcoding 0.75 ×
## 0.75, so a rebalance of either table moves the test with it. The storm-on-plains arm is the one
## that could not pass before the fix at all: terrain is 1.0 there, so the old caption was absent.

const BM_SRC := "res://src/battle/BattleManager.gd"

var _saved_weather: String = ""
var _saved_weather_timer: float = 0.0


func before_each() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and "weather_condition" in gs:
		_saved_weather = str(gs.weather_condition)
		_saved_weather_timer = float(gs.weather_timer)


func after_each() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and _saved_weather != "" and "weather_condition" in gs:
		gs.weather_condition = _saved_weather
		gs.weather_timer = _saved_weather_timer


func _set_weather(condition: String) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and "weather_condition" in gs:
		gs.weather_condition = condition
		gs.weather_timer = 100000.0


func _bm() -> Node:
	var bm: Node = load(BM_SRC).new()
	add_child_autofree(bm)
	return bm


func _caster() -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = "Mage"
	c.is_alive = true
	c.max_hp = 500
	c.current_hp = 500
	c.max_mp = 999
	c.current_mp = 999
	c.magic = 120
	return c


func _target() -> Combatant:
	var t: Combatant = autofree(Combatant.new())
	t.combatant_name = "Dummy"
	t.is_alive = true
	t.max_hp = 999999
	t.current_hp = 999999
	t.magic_defense = 20
	return t


## Every battle-log line the cast emitted.
func _cast_and_capture(bm: Node, terrain: String, weather: String, element: String) -> Array[String]:
	bm.set_terrain(terrain)
	_set_weather(weather)
	var lines: Array[String] = []
	bm.battle_log_message.connect(func(msg: String) -> void: lines.append(msg))
	var caster := _caster()
	var target := _target()
	bm.player_party.assign([caster] as Array[Combatant])
	bm.enemy_party.assign([target] as Array[Combatant])
	var ability := {"id": "probe_bolt", "name": "Probe", "type": "magic",
		"damage_multiplier": 2.0, "element": element, "mp_cost": 0}
	bm._execute_magic_ability(caster, ability, [target] as Array[Combatant])
	return lines


func _damage_line(lines: Array[String]) -> String:
	for l in lines:
		if l.contains("takes") and l.contains("damage"):
			return l
	return ""


func test_the_two_tables_disagree_enough_to_measure_with() -> void:
	var bm := _bm()
	bm.set_terrain("cave")
	assert_lt(float(bm.get_terrain_damage_modifier("fire")), 1.0,
		"CONTROL: cave must reduce fire, or the combined-factor arm proves nothing")
	_set_weather("rain")
	assert_lt(float(bm.get_weather_damage_modifier("fire")), 1.0,
		"CONTROL: rain must reduce fire, or terrain alone would be the whole effect")
	bm.set_terrain("plains")
	assert_eq(float(bm.get_terrain_damage_modifier("lightning")), 1.0,
		"CONTROL: plains must be the identity for lightning — the storm arm depends on it")


func test_a_storm_on_plains_is_named_at_all() -> void:
	## The arm that could not pass before the fix: terrain is 1.0, so the old caption was EMPTY
	## while the hit was scaled by weather alone.
	var bm := _bm()
	_set_weather("storm")
	if is_equal_approx(float(bm.get_weather_damage_modifier("lightning")), 1.0):
		pending("storm does not modify lightning in this build; the control arm reports the tables")
		return
	var line := _damage_line(_cast_and_capture(bm, "plains", "storm", "lightning"))
	assert_ne(line, "", "CONTROL: the cast must emit a damage line, or this arm reads an empty list")
	assert_true(line.contains("weather"),
		"terrain is the identity on plains, so weather is the ENTIRE modifier — a caption that "
		+ "names only terrain says nothing here while the hit moved: %s" % line)


func test_both_factors_are_named_when_both_moved() -> void:
	var bm := _bm()
	var line := _damage_line(_cast_and_capture(bm, "cave", "rain", "fire"))
	assert_ne(line, "", "CONTROL: the cast must emit a damage line")
	assert_true(line.contains("terrain") and line.contains("weather"),
		"cave reduces fire AND rain reduces fire; naming one of the two attributes half the "
		+ "reduction to the wrong cause: %s" % line)


func test_the_percentage_is_the_combined_factor_not_terrain_alone() -> void:
	## Derived from the engine's own resolvers, so a rebalance of either table moves this with it.
	var bm := _bm()
	bm.set_terrain("cave")
	_set_weather("rain")
	var t_mod: float = float(bm.get_terrain_damage_modifier("fire"))
	var w_mod: float = float(bm.get_weather_damage_modifier("fire"))
	var combined: int = int(round((1.0 - t_mod * w_mod) * 100.0))
	var terrain_only: int = int(round((1.0 - t_mod) * 100.0))
	assert_ne(combined, terrain_only,
		"CONTROL: the combined and terrain-only figures must differ, or this arm cannot tell them apart")
	var line := _damage_line(_cast_and_capture(bm, "cave", "rain", "fire"))
	assert_true(line.contains("-%d%%" % combined),
		"the caption must report the factor actually applied (-%d%%), not terrain's share (-%d%%): %s"
		% [combined, terrain_only, line])
