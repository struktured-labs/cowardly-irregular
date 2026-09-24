extends GutTest

## New Game emptied GameState.equipment_pool and left GameLoop.equipment_pool
## alone. The Equipment menu reads the live pool (OverworldMenu._shared_equipment_pool),
## and the next menu open syncs that pool back into the save bucket — so last
## run's unequipped drops survived Quit to Title → New Game and then got saved
## into the new playthrough. Same leak class as the grind meter: the bucket
## reset, the thing the player actually hears/sees did not.
##
## _create_party and _start_exploration are stubbed so this drives the new-game
## handler without building a map. A loaded save must still copy the bucket
## onto the live pool; that path is the control.

const GameLoopScript := preload("res://src/GameLoop.gd")
const BattleSceneScript := preload("res://src/battle/BattleScene.gd")

const LEAKED_WEAPON := "iron_sword"
const LEAKED_ARMOR := "leather_armor"
const LEAKED_ACCESSORY := "power_ring"

## In the tree only so the handler can await a frame. _ready would boot the title.
class QuietNewGame extends GameLoopScript:
	func _ready() -> void:
		pass
	func _create_party() -> void:
		pass
	func _start_exploration(_force_battle_teardown: bool = false) -> void:
		pass


var _saved_state: Dictionary = {}
var _saved_speed: float = 0.25
var _saved_encounter: float = 1.0
var _saved_speed_index: int = 0
var _saved_auto: Dictionary = {}
var _saved_cancel_all: bool = false
var _saved_legacy_auto: bool = false
var _saved_grind: float = 0.0
var _saved_intensity: float = 0.0
var _saved_target: float = 0.0


func before_each() -> void:
	_saved_state = GameState.to_dict()
	_saved_speed = GameState.default_battle_speed
	_saved_encounter = GameState.encounter_rate_multiplier
	_saved_speed_index = BattleSceneScript._battle_speed_index
	_saved_auto = AutobattleSystem.autobattle_enabled.duplicate()
	_saved_cancel_all = AutobattleSystem.cancel_all_next_turn
	_saved_legacy_auto = BattleManager.is_autobattle_enabled
	_saved_grind = SoundManager._grind_corruption
	_saved_intensity = SoundManager._corruption_intensity
	_saved_target = SoundManager._corruption_target


func after_each() -> void:
	GameState._apply_save_data(_saved_state)
	GameState.default_battle_speed = _saved_speed
	GameState.encounter_rate_multiplier = _saved_encounter
	BattleSceneScript._battle_speed_index = _saved_speed_index
	AutobattleSystem.autobattle_enabled = _saved_auto.duplicate()
	AutobattleSystem.cancel_all_next_turn = _saved_cancel_all
	BattleManager.is_autobattle_enabled = _saved_legacy_auto
	SoundManager._grind_corruption = _saved_grind
	SoundManager._corruption_intensity = _saved_intensity
	SoundManager._corruption_target = _saved_target
	if SaveSystem and SaveSystem.has_method("save_settings"):
		SaveSystem.save_settings()


func test_floor_the_new_game_gear_path() -> void:
	var gl: Node = autofree(GameLoopScript.new())
	for m in ["_on_title_new_game", "_init_equipment_pool", "_sync_party_to_game_state", "_restore_equipment_pool_from_game_state"]:
		assert_true(gl.has_method(m), "GameLoop must still expose %s()" % m)


func test_new_game_drops_last_runs_unequipped_gear() -> void:
	var gl: QuietNewGame = autofree(QuietNewGame.new())
	add_child(gl)
	gl.equipment_pool = {
		"weapons": [LEAKED_WEAPON],
		"armors": [LEAKED_ARMOR],
		"accessories": [LEAKED_ACCESSORY],
	}
	var cold: Node = autofree(GameLoopScript.new())
	cold._init_equipment_pool()
	await gl._on_title_new_game()
	assert_eq(gl.equipment_pool["weapons"], cold.equipment_pool["weapons"],
		"New Game left %s in the live weapon bag — the Equipment menu reads GameLoop.equipment_pool, and reset_game_state only empties the save bucket" % str(gl.equipment_pool["weapons"]))
	assert_eq(gl.equipment_pool["armors"], cold.equipment_pool["armors"],
		"New Game left %s in the live armor bag" % str(gl.equipment_pool["armors"]))
	assert_eq(gl.equipment_pool["accessories"], cold.equipment_pool["accessories"],
		"New Game left %s in the live accessory bag" % str(gl.equipment_pool["accessories"]))
	gl._sync_party_to_game_state()
	assert_false(GameState.equipment_pool["weapons"].has(LEAKED_WEAPON),
		"opening the menu synced last run's %s back into the save — the bucket clear does not survive the first menu" % LEAKED_WEAPON)
	assert_eq(GameState.equipment_pool["weapons"], cold.equipment_pool["weapons"],
		"the save bucket must match the reseeded live bag after the menu sync")


func test_a_loaded_save_still_puts_its_gear_in_the_live_bag() -> void:
	var gl: Node = autofree(GameLoopScript.new())
	gl._init_equipment_pool()
	GameState.equipment_pool = {
		"weapons": [LEAKED_WEAPON],
		"armors": [LEAKED_ARMOR],
		"accessories": [LEAKED_ACCESSORY],
	}
	gl._restore_equipment_pool_from_game_state()
	assert_eq(gl.equipment_pool["weapons"], [LEAKED_WEAPON],
		"Continue must still copy the saved bag onto the live pool — New Game is the path that reseeds")
	assert_eq(gl.equipment_pool["armors"], [LEAKED_ARMOR], "saved armor still restores")
	assert_eq(gl.equipment_pool["accessories"], [LEAKED_ACCESSORY], "saved accessories still restore")
