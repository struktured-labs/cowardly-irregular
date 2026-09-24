extends GutTest

## howl (wolf) authors secondary_target "all_enemies" and secondary_effect "fear".
## BattleManager resolved that tag against the enemy_party array, so a wolf
## frightened its own pack — and itself — while the party was spared.
## Fear skips the action half the time and halves the swings that still land.

const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const COMBATANT_PATH := "res://src/battle/Combatant.gd"

var _bm_guard = null


func before_each() -> void:
	_bm_guard = BattleStateGuard.new()
	_bm_guard.snapshot()


func after_each() -> void:
	if _bm_guard != null:
		_bm_guard.restore()


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 20,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func _authored_howl() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).get("howl", {})


func _battle_manager():
	return Engine.get_main_loop().root.get_node_or_null("BattleManager")


func _has_buff_effect(combatant: Combatant, effect: String) -> bool:
	for b in combatant.active_buffs:
		if str(b.get("effect", "")) == effect:
			return true
	return false


func test_a_wolfs_howl_frightens_the_party_not_its_pack() -> void:
	var bm = _battle_manager()
	if bm == null:
		pending("BattleManager autoload required")
		return
	var howl: Dictionary = _authored_howl()
	assert_eq(str(howl.get("secondary_target", "")), "all_enemies",
		"CONTROL: howl must still aim its secondary at all_enemies")
	assert_eq(str(howl.get("secondary_effect", "")), "fear",
		"CONTROL: howl's secondary must still be fear")
	assert_almost_eq(float(howl.get("secondary_chance", -1.0)), 0.3, 0.001,
		"CONTROL: the authored fear chance stays 0.3 — this test forces the roll, it does not retune it")
	var hero: Combatant = _make("Hero")
	var downed: Combatant = _make("Downed")
	downed.die()
	var wolf: Combatant = _make("Wolf")
	var packmate: Combatant = _make("Packmate")
	var players: Array[Combatant] = [hero, downed]
	var enemies: Array[Combatant] = [wolf, packmate]
	bm.player_party = players
	bm.enemy_party = enemies
	var cast: Dictionary = howl.duplicate(true)
	cast["secondary_chance"] = 1.0
	var targets: Array[Combatant] = [wolf]
	bm._execute_support_ability(wolf, cast, targets)
	assert_true(hero.has_status("fear"),
		"a wolf's howl must frighten the party — all_enemies is relative to the caster")
	assert_false(downed.has_status("fear"),
		"a KO'd party member is not a valid fear target")
	assert_false(packmate.has_status("fear"),
		"the wolf frightened its own packmate — all_enemies was the enemy roster, not the caster's foes")
	assert_false(wolf.has_status("fear"),
		"the howler frightened itself")
	assert_true(_has_buff_effect(wolf, "Berserk"),
		"howl's own attack buff must still land on the caster")


func test_an_enemy_all_allies_secondary_buffs_the_pack() -> void:
	var bm = _battle_manager()
	if bm == null:
		pending("BattleManager autoload required")
		return
	var hero: Combatant = _make("Hero")
	var wolf: Combatant = _make("Wolf")
	var packmate: Combatant = _make("Packmate")
	var players: Array[Combatant] = [hero]
	var enemies: Array[Combatant] = [wolf, packmate]
	bm.player_party = players
	bm.enemy_party = enemies
	var ability: Dictionary = {
		"id": "pack_howl_test",
		"type": "support",
		"effect": "attack_up",
		"stat_modifier": 1.2,
		"duration": 2,
		"secondary_target": "all_allies",
		"secondary_effect": "attack_up",
		"secondary_modifier": 1.1,
		"secondary_chance": 1.0,
	}
	var targets: Array[Combatant] = [wolf]
	bm._execute_support_ability(wolf, ability, targets)
	assert_true(_has_buff_effect(packmate, "Secondary Attack Up"),
		"an enemy's all_allies secondary must buff its pack")
	assert_true(_has_buff_effect(wolf, "Secondary Attack Up"),
		"the caster is one of its own allies")
	assert_false(_has_buff_effect(hero, "Secondary Attack Up"),
		"an enemy's all_allies secondary buffed the player party")
