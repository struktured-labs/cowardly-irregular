extends GutTest

## Front Line is +10% ATK and -10% DEF together. Back Row is the opposite trade.
## The bonus is stored as a buff and the penalty as a debuff, and every strip
## (dispel, dispel_one, Reduce Overhead, Optimization Itself) clears buffs only.
## After Void Breath or Optimize Away the party still stands in the row and the
## menu still names both halves, but the swing is unmodified and the penalty
## remains. A dispel must take spell buffs and leave the stance.

const BS_PATH := "res://src/battle/BattleScene.gd"

var _saved_formation: int = 0
var _saved_players: Array = []
var _saved_enemies: Array = []


func before_each() -> void:
	_saved_formation = int(load(BS_PATH).current_formation)
	if BattleManager:
		_saved_players = BattleManager.player_party.duplicate()
		_saved_enemies = BattleManager.enemy_party.duplicate()


func after_each() -> void:
	load(BS_PATH).current_formation = _saved_formation
	if BattleManager == null:
		return
	BattleManager.player_party.clear()
	BattleManager.enemy_party.clear()
	for c in _saved_players:
		BattleManager.player_party.append(c)
	for c in _saved_enemies:
		BattleManager.enemy_party.append(c)


func _member(nm: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": nm, "max_hp": 100, "max_mp": 40,
		"attack": 200, "defense": 100, "magic": 40, "speed": 12,
	})
	c.base_attack = 200
	c.base_defense = 100
	c.is_alive = true
	add_child_autofree(c)
	return c


func _stand(c: Combatant, formation: int) -> void:
	var scene: GDScript = load(BS_PATH)
	scene.current_formation = formation
	scene.apply_persisted_formation([c])


func _mod(c: Combatant, effect: String) -> float:
	for bucket in [c.active_buffs, c.active_debuffs]:
		for entry in bucket:
			if str(entry.get("effect", "")) == effect:
				return float(entry.get("modifier", 0.0))
	return -1.0


func _dispel(target: Combatant) -> void:
	var caster := _member("Dispeller")
	BattleManager._execute_support_ability(caster, {
		"id": "optimize_away",
		"type": "support",
		"effect": "dispel",
	}, [target])


func test_front_line_keeps_both_halves_when_a_spell_buff_is_dispelled() -> void:
	var scene: GDScript = load(BS_PATH)
	var pc := _member("Front")
	_stand(pc, scene.PartyFormation.FRONT_LINE)
	pc.add_buff("Protect", "defense", 1.5, 5)
	_dispel(pc)
	assert_eq(_mod(pc, "Protect"), -1.0,
		"a real spell buff is still stripped")
	assert_almost_eq(_mod(pc, "formation_atk"), 1.1, 0.001,
		"Front Line's +10% ATK is the row, not a spell — dispel must leave it")
	assert_almost_eq(_mod(pc, "formation_def"), 0.9, 0.001,
		"and the -10% DEF stays with it, or the row becomes a pure penalty")
	assert_eq(pc.get_buffed_stat("attack", pc.attack), int(float(pc.attack) * 1.1),
		"the swing is still the front-line hit")
	assert_eq(pc.get_buffed_stat("defense", pc.defense), int(float(pc.defense) * 0.9),
		"and incoming physical still uses the front-line defense")


func test_back_row_keeps_both_halves_when_dispelled() -> void:
	var scene: GDScript = load(BS_PATH)
	var pc := _member("Back")
	_stand(pc, scene.PartyFormation.BACK_ROW)
	pc.add_buff("Shell", "magic_defense", 1.4, 4)
	_dispel(pc)
	assert_eq(_mod(pc, "Shell"), -1.0, "Shell is a spell and still goes")
	assert_almost_eq(_mod(pc, "formation_def"), 1.1, 0.001,
		"Back Row's +10% DEF must survive dispel")
	assert_almost_eq(_mod(pc, "formation_atk"), 0.9, 0.001,
		"and the -10% ATK stays with it")
	assert_eq(pc.get_buffed_stat("defense", pc.defense), int(float(pc.defense) * 1.1))
	assert_eq(pc.get_buffed_stat("attack", pc.attack), int(float(pc.attack) * 0.9))


func test_dispel_one_cannot_pick_the_row() -> void:
	var scene: GDScript = load(BS_PATH)
	var pc := _member("One")
	_stand(pc, scene.PartyFormation.FRONT_LINE)
	var caster := _member("Picker")
	BattleManager._execute_support_ability(caster, {
		"id": "remove_element",
		"type": "support",
		"effect": "dispel_one",
	}, [pc])
	assert_almost_eq(_mod(pc, "formation_atk"), 1.1, 0.001,
		"the only buff on a front-liner is the row — dispel_one must not take it")
	assert_almost_eq(_mod(pc, "formation_def"), 0.9, 0.001,
		"the defense penalty stays paired with the attack bonus")


func test_reduce_overhead_strips_the_spell_and_leaves_the_row() -> void:
	var scene: GDScript = load(BS_PATH)
	var pc := _member("Overhead")
	var caster := _member("Caster")
	_stand(pc, scene.PartyFormation.FRONT_LINE)
	pc.add_buff("Power Up", "attack", 1.5, 3)
	BattleManager._execute_support_ability(caster, {
		"id": "reduce_overhead",
		"type": "support",
		"effect": "dispel_and_self_buff",
	}, [pc])
	assert_eq(_mod(pc, "Power Up"), -1.0, "Reduce Overhead still strips the spell buff")
	assert_almost_eq(_mod(pc, "formation_atk"), 1.1, 0.001,
		"it must not also un-stand them from Front Line")
	assert_almost_eq(_mod(pc, "formation_def"), 0.9, 0.001)
	assert_eq(pc.get_buffed_stat("attack", pc.attack), int(float(pc.attack) * 1.1),
		"the swing is the row's +10%, not the stripped Power Up and not bare attack")
	assert_eq(caster.active_buffs.size(), 1, "the caster still gets the self-buff")
	assert_eq(str(caster.active_buffs[0].get("effect", "")), "Overhead Reduced")


func test_optimization_itself_does_not_strip_the_row() -> void:
	if BattleManager == null or EncounterSystem == null:
		fail_test("BattleManager and EncounterSystem are required")
		return
	if not EncounterSystem.monster_database.has("optimization_itself"):
		fail_test("optimization_itself must be in the monster database")
		return
	var scene: GDScript = load(BS_PATH)
	var pc := _member("Optimized")
	_stand(pc, scene.PartyFormation.BACK_ROW)
	var optimizer := _member("Optimization")
	optimizer.set_meta("monster_type", "optimization_itself")
	var players: Array[Combatant] = [pc]
	var foes: Array[Combatant] = [optimizer]
	BattleManager.player_party = players
	BattleManager.enemy_party = foes
	BattleManager._apply_strip_buffs_on_round_start()
	assert_almost_eq(_mod(pc, "formation_def"), 1.1, 0.001,
		"Optimization Itself strips spell buffs, not the back-row defense")
	assert_almost_eq(_mod(pc, "formation_atk"), 0.9, 0.001,
		"and the attack penalty stays, so the row is still the trade the menu names")
	assert_eq(pc.get_buffed_stat("defense", pc.defense), int(float(pc.defense) * 1.1))
	assert_eq(pc.get_buffed_stat("attack", pc.attack), int(float(pc.attack) * 0.9))
