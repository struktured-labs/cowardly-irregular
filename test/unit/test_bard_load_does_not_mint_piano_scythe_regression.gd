extends GutTest

## Loading a save calls JobSystem.assign_job to rebuild the job dict. That same
## call is what hands a Bard with an empty weapon their Piano Scythe the first
## time they take the job. On a load, the save is the authority for what is
## worn: an empty hand means the player took the scythe off (into the bag, or
## sold it). Honoring the join gift here puts a weapon back in their hands.
## The bag copy is still there, so they own two, and the sold one grows back
## for another 225 gold.


const SCYTHE := "piano_scythe"
const GAME_LOOP := "res://src/GameLoop.gd"

var _gl: Node = null
var _saved_party: Array = []
var _saved_pool: Dictionary = {}
var _saved_world: int = 1
var _saved_map: String = ""
var _saved_pending: Vector2 = Vector2.INF


func before_each() -> void:
	_saved_party = GameState.player_party.duplicate(true)
	_saved_pool = GameState.equipment_pool.duplicate(true)
	_saved_world = GameState.current_world
	_saved_map = str(MapSystem.current_map_id) if MapSystem != null else ""
	_saved_pending = SaveSystem.pending_player_position
	assert_true(JobSystem.jobs.has("bard"), "bard job must exist or this test asks nothing")
	assert_true(EquipmentSystem.weapons.has(SCYTHE), "piano_scythe must be a real weapon")
	assert_gt(int(EquipmentSystem.get_weapon(SCYTHE).get("cost", 0)), 0,
		"the scythe must be sellable or the reload-and-sell loop is not a player path")


func after_each() -> void:
	if _gl != null and is_instance_valid(_gl):
		_gl.free()
		_gl = null
	GameState.player_party.clear()
	for entry in _saved_party:
		if entry is Dictionary:
			GameState.player_party.append(entry)
	GameState.equipment_pool = _saved_pool.duplicate(true)
	GameState.current_world = _saved_world
	if MapSystem != null and _saved_map != "":
		MapSystem.current_map_id = _saved_map
	SaveSystem.pending_player_position = _saved_pending


func test_an_empty_hand_with_the_scythe_in_the_bag_does_not_grow_a_second() -> void:
	var gl := _restore_bard("", [SCYTHE])
	var bard: Combatant = gl.party[0]
	assert_eq(str(bard.job.get("id", "")), "bard", "restore must still rebuild the bard job")
	assert_eq(bard.equipped_weapon, "",
		"a save with an empty hand must load with an empty hand, not the join-gift scythe")
	assert_eq((gl.equipment_pool["weapons"] as Array).count(SCYTHE), 1,
		"the scythe the player put in the bag must still be there, once")
	assert_eq(_scythes(gl), 1, "load must not mint a second Piano Scythe beside the bag copy")


func test_a_sold_scythe_does_not_grow_back_on_load() -> void:
	var gl := _restore_bard("", [])
	var bard: Combatant = gl.party[0]
	assert_eq(str(bard.job.get("id", "")), "bard")
	assert_eq(bard.equipped_weapon, "",
		"selling the scythe and saving empty-handed must not equip a new one on Continue")
	assert_eq((gl.equipment_pool["weapons"] as Array).count(SCYTHE), 0,
		"the bag must not gain a scythe the player already sold")
	assert_eq(_scythes(gl), 0, "load must not mint a Piano Scythe the save does not contain")


func test_a_scythe_the_save_says_is_worn_stays_worn() -> void:
	var gl := _restore_bard(SCYTHE, [])
	var bard: Combatant = gl.party[0]
	assert_eq(bard.equipped_weapon, SCYTHE,
		"a scythe the save says is equipped must still be equipped after load")
	assert_eq((gl.equipment_pool["weapons"] as Array).count(SCYTHE), 0,
		"the worn scythe must not also be copied into the bag")
	assert_eq(_scythes(gl), 1)


func _restore_bard(weapon_id: String, bag_weapons: Array) -> Node:
	GameState.player_party.clear()
	GameState.player_party.append({
		"name": "Bard",
		"job_id": "bard",
		"equipped_weapon": weapon_id,
		"equipped_armor": "",
		"equipped_accessory": "",
		"current_hp": 100,
		"max_hp": 100,
		"current_mp": 20,
		"max_mp": 20,
		"is_alive": true,
	})
	GameState.equipment_pool = {
		"weapons": bag_weapons.duplicate(),
		"armors": [],
		"accessories": [],
	}
	_gl = load(GAME_LOOP).new()
	assert_true(_gl._restore_party_from_save_data(), "restore must rebuild the saved party")
	assert_eq(_gl.party.size(), 1, "the saved bard must come back")
	return _gl


func _scythes(gl: Node) -> int:
	var n: int = (gl.equipment_pool.get("weapons", []) as Array).count(SCYTHE)
	for member in gl.party:
		if member != null and str(member.equipped_weapon) == SCYTHE:
			n += 1
	return n
