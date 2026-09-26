extends GutTest

## Spell preview applied weakness and resist AFTER the defense formula. The cast does the
## opposite: take_elemental_damage multiplies affinity, then take_damage runs amount²/(amount+def).
## That formula is not linear, so the menu over-quoted resists, under-quoted weaknesses, and
## [KILL] followed the wrong number. Variance stays out of the preview (it is a roll); this file
## pins that roll to 1x so the quoted number and the landed hit can be compared exactly. Magic
## does not crit, so there is no second roll to pin.

const FIRE := {"id": "pinned_fire", "type": "magic", "damage_multiplier": 2.0, "element": "fire"}

var _saved_weather: String = ""
var _saved_weather_timer: float = 0.0
var _saved_damage_multiplier: float = 1.0
var _bm: Node = null


class _PinnedVariance extends VolatilitySystem:
	func get_variance_range(_combatant) -> Vector2:
		return Vector2(1.0, 1.0)


func before_each() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and "weather_condition" in gs:
		_saved_weather = str(gs.weather_condition)
		_saved_weather_timer = float(gs.weather_timer)
		gs.weather_condition = "clear"
		gs.weather_timer = 100000.0
	if gs != null and "game_constants" in gs:
		_saved_damage_multiplier = float(gs.game_constants.get("damage_multiplier", 1.0))
		gs.game_constants["damage_multiplier"] = 1.0
	_bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(_bm)
	_bm.volatility = _PinnedVariance.new()
	_bm.set_terrain("plains")


func after_each() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and _saved_weather != "" and "weather_condition" in gs:
		gs.weather_condition = _saved_weather
		gs.weather_timer = _saved_weather_timer
	if gs != null and "game_constants" in gs:
		gs.game_constants["damage_multiplier"] = _saved_damage_multiplier


func _caster() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Mage"
	c.is_alive = true
	c.max_hp = 500
	c.current_hp = 500
	c.attack = 40
	c.magic = 100
	c.defense = 20
	c.magic_defense = 20
	return c


func _foe(kind: String) -> Combatant:
	var t := Combatant.new()
	autofree(t)
	t.combatant_name = kind
	t.is_alive = true
	t.max_hp = 99999
	t.current_hp = 99999
	t.defense = 40
	t.magic_defense = 40
	if kind == "weak":
		t.elemental_weaknesses.append("fire")
	elif kind == "resist":
		t.elemental_resistances.append("fire")
	return t


## The pre-fix quote: defend the raw hit, then scale. Kept only so this fixture can prove the two
## orders are not the same integer — a green comparison against an identical pair would not be a test.
func _affinity_after_defense(raw: int, defense: int, affinity: float) -> int:
	var mitigated := int((float(raw) * float(raw)) / float(maxi(1, raw + defense)))
	return maxi(1, int(float(maxi(1, mitigated)) * affinity))


func _landed(caster: Combatant, target: Combatant) -> int:
	var before := target.current_hp
	_bm._execute_magic_ability(caster, FIRE, [target])
	return before - target.current_hp


func test_the_preview_matches_the_hit_on_a_weak_and_a_resistant_target() -> void:
	var roll: Vector2 = _bm.volatility.get_variance_range(_caster())
	assert_eq(roll, Vector2(1.0, 1.0),
		"CONTROL: the damage roll must be pinned to 1x, or variance can fake a mismatch")
	var caster := _caster()
	var raw := int(caster.magic * float(FIRE["damage_multiplier"]))
	var weak_after := _affinity_after_defense(raw, 40, 1.5)
	var resist_after := _affinity_after_defense(raw, 40, 0.5)
	var weak_before := maxi(1, int((float(int(raw * 1.5)) * float(int(raw * 1.5))) / float(int(raw * 1.5) + 40)))
	var resist_before := maxi(1, int((float(int(raw * 0.5)) * float(int(raw * 0.5))) / float(int(raw * 0.5) + 40)))
	assert_ne(weak_after, weak_before, "CONTROL: weakness must separate the two orders on this fixture")
	assert_ne(resist_after, resist_before, "CONTROL: resist must separate the two orders on this fixture")
	var weak := _foe("weak")
	var resist := _foe("resist")
	var preview_weak: int = _bm.estimate_ability_damage(caster, weak, FIRE)
	var preview_resist: int = _bm.estimate_ability_damage(caster, resist, FIRE)
	var hit_weak := _landed(caster, weak)
	var hit_resist := _landed(caster, resist)
	assert_gt(hit_weak, hit_resist,
		"CONTROL: the cast itself must hit a weakness harder than a resist (weak %d, resist %d)" % [hit_weak, hit_resist])
	assert_eq(preview_weak, hit_weak,
		"a fire weakness must preview the hit that lands — after-defense quotes low (preview %d, hit %d, old order %d)" % [preview_weak, hit_weak, weak_after])
	assert_eq(preview_resist, hit_resist,
		"a fire resist must preview the hit that lands — after-defense quotes high (preview %d, hit %d, old order %d)" % [preview_resist, hit_resist, resist_after])
