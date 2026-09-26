extends GutTest

## The blacksmith sells the Flame Sword (fire_damage_bonus 1.5) and the Mage starts with Ignis.
## The swing multiplies that bonus in before defense. The "~N dmg" row and its [KILL] tag did not,
## so a killing Fire looked short and a non-killing one looked even shorter. Same gap for the
## element_boost buff, which execution folds into the same multiplier.

var _saved_weather: String = ""
var _saved_weather_timer: float = 0.0
var _saved_terrain: String = ""


func before_each() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and "weather_condition" in gs:
		_saved_weather = str(gs.weather_condition)
		_saved_weather_timer = float(gs.weather_timer)
		gs.weather_condition = "clear"
		gs.weather_timer = 100000.0
	_saved_terrain = str(BattleManager._current_terrain)
	BattleManager.set_terrain("plains")


func after_each() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and _saved_weather != "" and "weather_condition" in gs:
		gs.weather_condition = _saved_weather
		gs.weather_timer = _saved_weather_timer
	BattleManager.set_terrain(_saved_terrain)


func _caster() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Mage"
	c.is_alive = true
	c.max_hp = 400
	c.current_hp = 400
	c.attack = 40
	c.magic = 100
	c.defense = 20
	c.magic_defense = 20
	return c


func _foe() -> Combatant:
	var t := Combatant.new()
	autofree(t)
	t.combatant_name = "Goblin"
	t.is_alive = true
	t.max_hp = 9999
	t.current_hp = 9999
	t.defense = 40
	t.magic_defense = 20
	return t


## The pre-defense scale _execute_magic_ability bakes, then the defense formula the preview uses.
func _scaled(stat: int, mult: float, scale: float, defense: int) -> int:
	var raw := int(float(stat) * mult * scale)
	return maxi(1, int((float(raw) * float(raw)) / float(maxi(1, raw + defense))))


func _fire_bonus() -> float:
	var weapon: Dictionary = EquipmentSystem.get_weapon("flame_sword")
	var effects: Variant = weapon.get("special_effects", {})
	if effects is Dictionary:
		return float(effects.get("fire_damage_bonus", 0.0))
	return 0.0


func test_a_flame_sword_raises_the_fire_preview_by_its_authored_bonus() -> void:
	var bonus := _fire_bonus()
	assert_gt(bonus, 1.0, "CONTROL: the Flame Sword still authors a fire damage bonus above 1 — got %s" % bonus)
	var fire: Dictionary = JobSystem.get_ability("fire")
	assert_eq(str(fire.get("element", "")), "fire", "CONTROL: Ignis is still the fire spell")
	assert_gt(float(fire.get("damage_multiplier", 0.0)), 0.0, "CONTROL: Ignis still deals damage")
	var bare := _caster()
	var armed := _caster()
	armed.equipped_weapon = "flame_sword"
	var foe := _foe()
	var mult := float(fire.get("damage_multiplier", 1.0))
	var unarmed := _scaled(bare.magic, mult, 1.0, foe.magic_defense)
	var with_sword := _scaled(armed.magic, mult, bonus, foe.magic_defense)
	assert_gt(with_sword, unarmed, "CONTROL: the bonus must move the number (%d vs %d)" % [with_sword, unarmed])
	assert_eq(BattleManager.estimate_ability_damage(bare, foe, fire), unarmed,
		"an unarmed Ignis still previews the plain magic hit")
	var preview := BattleManager.estimate_ability_damage(armed, foe, fire)
	assert_eq(preview, with_sword,
		"Flame Sword Ignis must preview %d (×%s before defense), not the unarmed %d — got %d" % [with_sword, bonus, unarmed, preview])
	var working: String = str(BattleManager.estimate_ability_breakdown(armed, foe, fire)["formula"])
	assert_true(working.contains("×gear %.2f" % bonus),
		"Formula Sight must show the sword's fire scale (%s)" % working)
	armed.equipped_weapon = ""
	assert_eq(BattleManager.estimate_ability_damage(armed, foe, fire), unarmed,
		"unequipping the sword puts the preview back")


func test_the_sword_does_not_scale_a_different_element_or_a_swing() -> void:
	var bonus := _fire_bonus()
	assert_gt(bonus, 1.0, "CONTROL: the Flame Sword still authors a fire damage bonus")
	var caster := _caster()
	caster.equipped_weapon = "flame_sword"
	var foe := _foe()
	var ice: Dictionary = JobSystem.get_ability("blizzard")
	assert_eq(str(ice.get("element", "")), "ice", "CONTROL: Blizzard is still ice")
	var ice_mult := float(ice.get("damage_multiplier", 1.0))
	assert_eq(BattleManager.estimate_ability_damage(caster, foe, ice), _scaled(caster.magic, ice_mult, 1.0, foe.magic_defense),
		"a fire sword does not raise an ice spell")
	var swing := {"type": "physical", "damage_multiplier": 2.0, "element": "fire"}
	assert_eq(BattleManager.estimate_ability_damage(caster, foe, swing), _scaled(caster.attack, 2.0, 1.0, foe.defense),
		"the fire bonus is a spell scale — a swing keeps the attack preview")


func test_an_element_boost_buff_reaches_the_same_preview() -> void:
	var caster := _caster()
	caster.active_buffs.append({"stat": "fire_damage", "modifier": 1.4, "duration": 3})
	var foe := _foe()
	var fire: Dictionary = JobSystem.get_ability("fire")
	var mult := float(fire.get("damage_multiplier", 1.0))
	var expected := _scaled(caster.magic, mult, 1.4, foe.magic_defense)
	assert_eq(BattleManager.estimate_ability_damage(caster, foe, fire), expected,
		"an element_boost on fire must preview ×1.4 before defense — got %d, want %d" % [
			BattleManager.estimate_ability_damage(caster, foe, fire), expected])
	caster.equipped_weapon = "flame_sword"
	var bonus := _fire_bonus()
	var stacked := _scaled(caster.magic, mult, bonus * 1.4, foe.magic_defense)
	assert_eq(BattleManager.estimate_ability_damage(caster, foe, fire), stacked,
		"sword and element_boost multiply, the way the cast does — got %d, want %d" % [
			BattleManager.estimate_ability_damage(caster, foe, fire), stacked])
