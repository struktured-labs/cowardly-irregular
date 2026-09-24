extends GutTest

## Front Line and Back Row are a static on BattleScene, and the sprites plus the
## command-menu label already follow that static into the next fight. The attack
## and defense do not. start_battle clears every buff — that wipe is correct,
## Protect must not leak — and nothing put the row back. The party still stands
## in Front Line, the menu still says "+10% ATK, -10% DEF", and the swing is
## unmodified until the player cycles the row again.
##
## A leftover formation_atk at 2.0x is planted before the call. After a real
## start_battle the modifier must be the row's 1.1, not the leftover, and a
## Protect planted beside it must be gone. That is the wipe and the reapply,
## in that order. Calling apply_persisted_formation by itself would keep Protect.

const BS_PATH := "res://src/battle/BattleScene.gd"

var _saved_formation: int = 0
var _started: bool = false


func before_each() -> void:
	_saved_formation = int(load(BS_PATH).current_formation)
	_started = false


func after_each() -> void:
	if _started and BattleManager and BattleManager.has_method("_cleanup_battle"):
		BattleManager._cleanup_battle()
	load(BS_PATH).current_formation = _saved_formation


func _member(alive: bool) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Row Probe" if alive else "Row Fallen"
	c.attack = 200
	c.defense = 100
	c.max_hp = 100
	c.current_hp = 100 if alive else 0
	c.is_alive = alive
	add_child_autofree(c)
	return c


func _plant_leftovers(c: Combatant) -> void:
	c.add_buff("formation_atk", "attack", 2.0, 999)
	c.add_buff("protect", "defense", 1.5, 5)


func _begin(members: Array, formation: int) -> void:
	if _started and BattleManager and BattleManager.has_method("_cleanup_battle"):
		BattleManager._cleanup_battle()
	var scene: GDScript = load(BS_PATH)
	scene.current_formation = formation
	var party: Array[Combatant] = []
	var foes: Array[Combatant] = []
	for member in members:
		party.append(member)
	var slime := Combatant.new()
	slime.combatant_name = "Row Slime"
	slime.max_hp = 10
	slime.current_hp = 10
	slime.is_alive = true
	add_child_autofree(slime)
	foes.append(slime)
	_started = true
	BattleManager.start_battle(party, foes)


func _mod(c: Combatant, effect: String) -> float:
	for bucket in [c.active_buffs, c.active_debuffs]:
		for entry in bucket:
			if str(entry.get("effect", "")) == effect:
				return float(entry.get("modifier", 0.0))
	return -1.0


func _count(c: Combatant, effect: String) -> int:
	var n := 0
	for bucket in [c.active_buffs, c.active_debuffs]:
		for entry in bucket:
			if str(entry.get("effect", "")) == effect:
				n += 1
	return n


func test_front_line_comes_back_after_the_buff_wipe() -> void:
	var scene: GDScript = load(BS_PATH)
	var pc := _member(true)
	var fallen := _member(false)
	_plant_leftovers(pc)
	_plant_leftovers(fallen)
	_begin([pc, fallen], scene.PartyFormation.FRONT_LINE)
	assert_almost_eq(_mod(pc, "formation_atk"), 1.1, 0.001,
		"Front Line must put +10% ATK back after start_battle clears the previous fight's buffs")
	assert_almost_eq(_mod(pc, "formation_def"), 0.9, 0.001,
		"and the matching -10% DEF, or the menu's Front Line line is a lie")
	assert_eq(_mod(pc, "protect"), -1.0,
		"the general buff wipe still happens — the row is reapplied, Protect is not carried in")
	assert_gt(pc.get_buffed_stat("attack", pc.attack), pc.attack,
		"the row has to change the swing, not only sit in the buff list")
	assert_lt(pc.get_buffed_stat("defense", pc.defense), pc.defense,
		"Front Line's defense penalty has to reach the number battle actually uses")
	assert_eq(_mod(fallen, "formation_atk"), -1.0,
		"a KO'd member does not take the row — they are not in the line")
	assert_eq(_mod(fallen, "protect"), -1.0,
		"and the wipe still clears whatever they were wearing when they fell")


func test_back_row_is_the_opposite_trade() -> void:
	var scene: GDScript = load(BS_PATH)
	var pc := _member(true)
	_plant_leftovers(pc)
	_begin([pc], scene.PartyFormation.BACK_ROW)
	assert_almost_eq(_mod(pc, "formation_def"), 1.1, 0.001,
		"Back Row is +10% DEF")
	assert_almost_eq(_mod(pc, "formation_atk"), 0.9, 0.001,
		"and -10% ATK — the leftover 2.0x attack buff must not win")
	assert_gt(pc.get_buffed_stat("defense", pc.defense), pc.defense)
	assert_lt(pc.get_buffed_stat("attack", pc.attack), pc.attack)


func test_a_row_with_no_stat_line_stays_unmodified() -> void:
	var scene: GDScript = load(BS_PATH)
	var pc := _member(true)
	_plant_leftovers(pc)
	_begin([pc], scene.PartyFormation.V_FORMATION)
	assert_eq(_mod(pc, "formation_atk"), -1.0,
		"V-Formation has no attack line — the planted 2.0x must not survive the wipe")
	assert_eq(_mod(pc, "formation_def"), -1.0)
	assert_eq(_mod(pc, "protect"), -1.0)
	assert_eq(pc.get_buffed_stat("attack", pc.attack), pc.attack,
		"and the swing is the unmodified attack")


func test_diamond_and_spread_keep_no_stat_line() -> void:
	var scene: GDScript = load(BS_PATH)
	var checked := 0
	for formation in [scene.PartyFormation.DIAMOND, scene.PartyFormation.SPREAD]:
		var pc := _member(true)
		pc.attack = 200
		_plant_leftovers(pc)
		_begin([pc], formation)
		assert_eq(_mod(pc, "formation_atk"), -1.0,
			"Diamond and Spread have no attack line — the planted 2.0x must not survive the wipe")
		assert_eq(_mod(pc, "formation_def"), -1.0)
		assert_eq(_mod(pc, "protect"), -1.0,
			"and Protect is still cleared — the row reapply did not replace the buff wipe")
		assert_eq(pc.get_buffed_stat("attack", pc.attack), pc.attack)
		checked += 1
	assert_eq(checked, 2, "both formations were actually driven")


func test_the_row_does_not_stack_across_battles() -> void:
	var scene: GDScript = load(BS_PATH)
	var pc := _member(true)
	pc.attack = 200
	_plant_leftovers(pc)
	_begin([pc], scene.PartyFormation.FRONT_LINE)
	assert_eq(_count(pc, "formation_atk"), 1)
	_begin([pc], scene.PartyFormation.FRONT_LINE)
	assert_eq(_count(pc, "formation_atk"), 1,
		"a second battle replaces the row; it must not leave two formation_atk entries")
	assert_almost_eq(_mod(pc, "formation_atk"), 1.1, 0.001)
	assert_eq(_count(pc, "formation_def"), 1)
	assert_almost_eq(_mod(pc, "formation_def"), 0.9, 0.001)
	assert_eq(pc.get_buffed_stat("attack", pc.attack), int(float(pc.attack) * 1.1),
		"two battles of Front Line are +10% once, not +21%")


func test_changing_formation_and_back_does_not_double() -> void:
	var scene: GDScript = load(BS_PATH)
	var pc := _member(true)
	pc.attack = 200
	pc.defense = 100
	scene.current_formation = scene.PartyFormation.FRONT_LINE
	scene.apply_persisted_formation([pc])
	scene.current_formation = scene.PartyFormation.BACK_ROW
	scene.apply_persisted_formation([pc])
	scene.current_formation = scene.PartyFormation.FRONT_LINE
	scene.apply_persisted_formation([pc])
	assert_eq(_count(pc, "formation_atk"), 1,
		"Front, then Back, then Front again is one attack modifier")
	assert_eq(_count(pc, "formation_def"), 1)
	assert_almost_eq(_mod(pc, "formation_atk"), 1.1, 0.001)
	assert_almost_eq(_mod(pc, "formation_def"), 0.9, 0.001)
	assert_eq(pc.get_buffed_stat("attack", pc.attack), int(float(pc.attack) * 1.1))
	assert_eq(pc.get_buffed_stat("defense", pc.defense), int(float(pc.defense) * 0.9))


func test_revive_follows_the_mid_fight_rule() -> void:
	var scene: GDScript = load(BS_PATH)
	var fallen := _member(false)
	_plant_leftovers(fallen)
	_begin([fallen], scene.PartyFormation.FRONT_LINE)
	assert_eq(_mod(fallen, "formation_atk"), -1.0,
		"a KO at battle start is not in the line")
	assert_eq(_mod(fallen, "protect"), -1.0)
	fallen.revive(40)
	assert_true(fallen.is_alive)
	assert_eq(_mod(fallen, "formation_atk"), -1.0,
		"revive() does not grant the row — a mid-fight raise never did")
	scene.apply_persisted_formation([fallen])
	assert_eq(_count(fallen, "formation_atk"), 1)
	assert_almost_eq(_mod(fallen, "formation_atk"), 1.1, 0.001,
		"the next apply, which is what changing formation does, includes them once they are standing")
	fallen.current_hp = 0
	fallen.is_alive = false
	fallen.revive(40)
	_begin([fallen], scene.PartyFormation.FRONT_LINE)
	assert_eq(_count(fallen, "formation_atk"), 1,
		"a member raised before the next battle is alive at the reapply and gets the row once")
	assert_almost_eq(_mod(fallen, "formation_atk"), 1.1, 0.001)


func test_a_save_roundtrip_keeps_one_row() -> void:
	var scene: GDScript = load(BS_PATH)
	var pc := _member(true)
	pc.attack = 200
	_plant_leftovers(pc)
	_begin([pc], scene.PartyFormation.FRONT_LINE)
	var parsed: Variant = JSON.parse_string(JSON.stringify(pc.to_dict()))
	assert_true(parsed is Dictionary, "the combatant save must round-trip through JSON")
	var loaded := Combatant.new()
	add_child_autofree(loaded)
	loaded.from_dict(parsed)
	assert_almost_eq(_mod(loaded, "formation_atk"), 1.1, 0.001,
		"the row buff is in the save")
	assert_eq(_mod(loaded, "protect"), -1.0,
		"Protect was wiped before the snapshot and must not come back from the file")
	_begin([loaded], scene.PartyFormation.FRONT_LINE)
	assert_eq(_count(loaded, "formation_atk"), 1,
		"loading the buff and starting a battle reapplies the row once — the saved 1.1 must not stack")
	assert_almost_eq(_mod(loaded, "formation_atk"), 1.1, 0.001)
	assert_eq(_mod(loaded, "protect"), -1.0)
	assert_eq(loaded.get_buffed_stat("attack", loaded.attack), int(float(loaded.attack) * 1.1))


func test_headless_grind_reapplies_the_same_row() -> void:
	var scene: GDScript = load(BS_PATH)
	var resolver = load("res://src/autogrind/HeadlessBattleResolver.gd").new()
	var hero := _member(true)
	hero.combatant_name = "Formation Grind Probe"
	hero.attack = 200
	hero.defense = 100
	hero.max_hp = 500
	hero.current_hp = 500
	hero.speed = 30
	_plant_leftovers(hero)
	var fallen := _member(false)
	_plant_leftovers(fallen)
	scene.current_formation = scene.PartyFormation.FRONT_LINE
	resolver.resolve_battle([hero, fallen], [_chaff()])
	assert_eq(_count(hero, "formation_atk"), 1,
		"a headless battle is still a battle — Front Line's +10% ATK has to be there")
	assert_almost_eq(_mod(hero, "formation_atk"), 1.1, 0.001)
	assert_eq(_count(hero, "formation_def"), 1)
	assert_almost_eq(_mod(hero, "formation_def"), 0.9, 0.001)
	assert_eq(_mod(hero, "protect"), -1.0,
		"the grind wipe still drops Protect; the row is put back, the leftover is not")
	assert_eq(hero.get_buffed_stat("attack", hero.attack), int(float(hero.attack) * 1.1))
	assert_eq(_mod(fallen, "formation_atk"), -1.0,
		"a KO'd member is skipped on the grind path too")
	assert_eq(_mod(fallen, "protect"), -1.0)
	resolver.resolve_battle([hero, fallen], [_chaff()])
	assert_eq(_count(hero, "formation_atk"), 1,
		"a second grind battle must not stack the row on the buff the first one left behind")
	assert_almost_eq(_mod(hero, "formation_atk"), 1.1, 0.001)
	assert_eq(hero.get_buffed_stat("attack", hero.attack), int(float(hero.attack) * 1.1))
	scene.current_formation = scene.PartyFormation.V_FORMATION
	hero.add_buff("formation_atk", "attack", 2.0, 999)
	hero.add_buff("protect", "defense", 1.5, 5)
	assert_almost_eq(_mod(hero, "formation_atk"), 2.0, 0.001,
		"precondition: the leftover row is stronger than Front Line, so a refresh-in-place would keep 2.0x")
	assert_almost_eq(_mod(hero, "protect"), 1.5, 0.001)
	resolver.resolve_battle([hero], [_chaff()])
	assert_eq(_mod(hero, "formation_atk"), -1.0,
		"V-Formation still has no attack line on the grind — the planted 2.0x must not survive")
	assert_eq(_mod(hero, "protect"), -1.0)


func _chaff() -> Combatant:
	var foe := Combatant.new()
	foe.combatant_name = "Row Chaff"
	foe.max_hp = 1
	foe.current_hp = 1
	foe.attack = 1
	foe.defense = 0
	foe.speed = 1
	foe.is_alive = true
	add_child_autofree(foe)
	return foe
