extends GutTest

## Warden and Arbiter tilts are baked into defense, max HP, and attack inside
## recalculate_stats. Equipping or handing off a Lens only wrote the assignment,
## so the status screen and the next fight kept the old numbers — and taking
## the Lens off left the bonus in place until some unrelated recalc.

const _DEF_BASE := 1000
const _HP_BASE := 1000


class _PartyHost:
	extends Node
	var party: Array = []


var _saved_recipes: Array[String] = []
var _saved_owned: Array[String] = []
var _saved_assign: Dictionary = {}
var _host: Node = null


func before_each() -> void:
	_saved_recipes = GameState.unlocked_lens_recipes.duplicate()
	_saved_owned = GameState.owned_lenses.duplicate()
	_saved_assign = GameState.lens_assignments.duplicate()
	GameState.unlocked_lens_recipes.clear()
	GameState.owned_lenses.clear()
	GameState.lens_assignments.clear()
	assert_null(get_tree().root.get_node_or_null("GameLoop"),
		"a GameLoop is already in the tree — this test would refresh the wrong party")
	_host = _PartyHost.new()
	_host.name = "GameLoop"
	get_tree().root.add_child(_host)


func after_each() -> void:
	GameState.unlocked_lens_recipes = _saved_recipes
	GameState.owned_lenses = _saved_owned
	GameState.lens_assignments = _saved_assign
	if _host != null and is_instance_valid(_host):
		_host.free()
		_host = null


func test_equipping_the_warden_lens_changes_defense_and_hp_immediately() -> void:
	var fighter := _member("Fighter")
	var defense_before: int = fighter.defense
	var hp_before: int = fighter.max_hp
	GameState.owned_lenses.append("warden")
	assert_true(LensSystem.equip_lens("fighter", "warden"))
	var mult: float = _tilt("warden", "defense_multiplier")
	var hp_mult: float = _tilt("warden", "max_hp_multiplier")
	assert_eq(fighter.defense, int(defense_before * mult),
		"wearing the Warden Lens must raise the defense the status screen and battles read")
	assert_eq(fighter.max_hp, int(hp_before * hp_mult),
		"and the max HP, which is baked in the same pass")
	assert_true(LensSystem.unequip_lens("fighter"))
	assert_eq(fighter.defense, defense_before,
		"taking the Lens off must drop defense back — the bonus must not stick")
	assert_eq(fighter.max_hp, hp_before,
		"and max HP with it")


func test_moving_the_lens_moves_the_baked_bonus() -> void:
	var fighter := _member("Fighter")
	var cleric := _member("Cleric")
	var fighter_before: int = fighter.defense
	var cleric_before: int = cleric.defense
	GameState.owned_lenses.append("warden")
	LensSystem.equip_lens("fighter", "warden")
	var mult: float = _tilt("warden", "defense_multiplier")
	assert_eq(fighter.defense, int(fighter_before * mult),
		"the Fighter's defense must include the Warden tilt as soon as the Lens is worn")
	assert_eq(cleric.defense, cleric_before,
		"a Lens on the Fighter must not raise the Cleric")
	LensSystem.equip_lens("cleric", "warden")
	assert_eq(fighter.defense, fighter_before,
		"the previous wearer loses the defense when the Lens moves")
	assert_eq(cleric.defense, int(cleric_before * mult),
		"the new wearer gains it in the same step")


func _tilt(axis: String, key: String) -> float:
	var mods: Dictionary = LensSystem.get_lens(axis).get("stat_mods", {})
	return float(mods.get(key, 1.0))


func _member(who: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = who
	c.base_defense = _DEF_BASE
	c.base_max_hp = _HP_BASE
	add_child(c)
	c.recalculate_stats()
	_host.party.append(c)
	return c
