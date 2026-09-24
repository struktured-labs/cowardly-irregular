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
