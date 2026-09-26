extends GutTest

## struktured 2026-08-15: "restarted game after dying from rat king and my
## entire party is KO'ed yet I'm walking around the dungeon."
## Mechanism: after a wipe the battle goes INACTIVE, the GameOverScreen is not
## a battle/interior/cutscene, so the 5-minute timed autosave passed
## can_quick_save() and snapshotted the dead party; Continue loaded it.
## Two floors: (1) no save path may capture a full wipe, (2) loading an
## already-poisoned save revives everyone at 1 HP so it is at least playable.

const STALE_HEALTHY_SLOT := 94
const BYPASS_WIPE_SLOT := 93
const LIVING_SAVE_SLOT := 92

var _saved_party: Array[Dictionary] = []
var _saved_battle_state: int = 0
var _saved_slot: int = 0
var _sync_fired: bool = false


func before_each() -> void:
	_saved_party = GameState.player_party.duplicate(true)
	# A prior suite test can leak an active battle in the BattleManager autoload —
	# _save_block_reason would then return "during battle" before the wiped check.
	_saved_battle_state = BattleManager.current_state
	BattleManager.current_state = BattleManager.BattleState.INACTIVE
	_saved_slot = SaveSystem.current_save_slot
	_sync_fired = false


func after_each() -> void:
	if SaveSystem.pre_save_sync.is_connected(_replace_party_with_wipe):
		SaveSystem.pre_save_sync.disconnect(_replace_party_with_wipe)
	for slot in [STALE_HEALTHY_SLOT, BYPASS_WIPE_SLOT, LIVING_SAVE_SLOT]:
		if SaveSystem.save_exists(slot):
			SaveSystem.delete_save(slot)
	SaveSystem.current_save_slot = _saved_slot
	GameState.player_party = _saved_party
	BattleManager.current_state = _saved_battle_state


func _wiped_party() -> Array:
	return [
		{"name": "Fighter", "job_id": "fighter", "is_alive": false, "current_hp": 0},
		{"name": "Cleric", "job_id": "cleric", "is_alive": false, "current_hp": 0},
	]


func _set_party(arr: Array) -> void:
	var typed: Array[Dictionary] = []
	for m in arr:
		typed.append(m)
	GameState.player_party = typed


func test_cannot_save_with_the_whole_party_down() -> void:
	_set_party(_wiped_party())
	assert_false(SaveSystem.can_quick_save(), "a full wipe must block every save path")
	assert_eq(SaveSystem._save_block_reason(), "Cannot save with the whole party down",
		"the block surfaces its real reason")


func test_one_survivor_keeps_saving_allowed() -> void:
	var party := _wiped_party()
	party[1] = {"name": "Cleric", "job_id": "cleric", "is_alive": true, "current_hp": 12}
	_set_party(party)
	assert_false(SaveSystem._party_is_wiped(), "one living member is not a wipe")


func test_empty_party_is_not_treated_as_wiped() -> void:
	_set_party([])
	assert_false(SaveSystem._party_is_wiped(),
		"pre-party states (title/new game) must not block the save system")


func test_loading_a_poisoned_save_revives_everyone_at_1_hp() -> void:
	SaveSystem._deserialize_party(_wiped_party())
	assert_eq(GameState.player_party.size(), 2, "party hydrated")
	for m in GameState.player_party:
		assert_true(bool(m.get("is_alive")), "%s revived by the wipe-rescue floor" % m.get("name"))
		assert_eq(int(m.get("current_hp")), 1, "%s at exactly 1 HP — playable, still punished" % m.get("name"))


func test_healthy_save_loads_untouched() -> void:
	SaveSystem._deserialize_party([
		{"name": "Fighter", "job_id": "fighter", "is_alive": true, "current_hp": 340},
		{"name": "Cleric", "job_id": "cleric", "is_alive": false, "current_hp": 0},
	])
	assert_eq(int(GameState.player_party[0].get("current_hp")), 340, "living member's HP untouched")
	assert_false(bool(GameState.player_party[1].get("is_alive")),
		"a partial KO is legitimate state — the floor fires only on a FULL wipe")


func _living_party() -> Array:
	return [
		{"name": "Fighter", "job_id": "fighter", "is_alive": true, "current_hp": 40, "max_hp": 40},
		{"name": "Cleric", "job_id": "cleric", "is_alive": true, "current_hp": 28, "max_hp": 28},
	]


## Stand-in for GameLoop's pre_save_sync listener: live combatants land after can_quick_save already passed.
func _replace_party_with_wipe() -> void:
	_sync_fired = true
	_set_party(_wiped_party())


func test_a_stale_healthy_snapshot_cannot_save_the_wipe_the_sync_just_flushed() -> void:
	_set_party(_living_party())
	SaveSystem.pre_save_sync.connect(_replace_party_with_wipe)
	var wrote: bool = SaveSystem.save_game(STALE_HEALTHY_SLOT)
	assert_true(_sync_fired, "pre_save_sync must run — the wipe lands after the early can_quick_save gate")
	assert_false(wrote, "save_game must refuse once the synced party is fully down")
	assert_false(SaveSystem.save_exists(STALE_HEALTHY_SLOT), "a refused wipe must not leave a slot Continue can load")
	assert_eq(int(GameState.player_party[0].get("current_hp")), 40,
		"refusing the wipe restores the pre-sync party so a later Retry can still autosave")


func test_force_quick_save_cannot_bypass_a_wipe_the_sync_just_flushed() -> void:
	_set_party(_living_party())
	SaveSystem.pre_save_sync.connect(_replace_party_with_wipe)
	var wrote: bool = SaveSystem.force_quick_save(BYPASS_WIPE_SLOT)
	assert_true(_sync_fired, "pre_save_sync must run under the meta bypass too")
	assert_false(wrote, "force_quick_save skips the early gate, so the post-sync wipe check has to refuse")
	assert_false(SaveSystem.save_exists(BYPASS_WIPE_SLOT), "a bypassed wipe must not write the quicksave slot")
	assert_eq(int(GameState.player_party[0].get("current_hp")), 40,
		"the bypass path restores the pre-sync party the same way a normal save does")


func test_a_living_party_still_saves_after_the_sync() -> void:
	_set_party(_living_party())
	var wrote: bool = SaveSystem.save_game(LIVING_SAVE_SLOT)
	assert_true(wrote, "a living party must still save — the post-sync check only refuses a wipe")
	assert_true(SaveSystem.save_exists(LIVING_SAVE_SLOT), "the living save must land on disk")
	assert_eq(int(GameState.player_party[0].get("current_hp")), 40, "a normal save leaves the living party in place")


func test_apply_save_data_revives_after_game_state_overwrites_the_party_rescue() -> void:
	var wiped := _wiped_party()
	var gs: Dictionary = GameState.to_dict()
	gs["player_party"] = wiped
	SaveSystem._apply_save_data({
		"party": wiped,
		"game_state": gs,
	})
	assert_eq(GameState.player_party.size(), 2, "party hydrated from the poisoned save")
	for m in GameState.player_party:
		assert_true(bool(m.get("is_alive")),
			"%s stayed down — game_state.player_party overwrites the 1 HP rescue" % m.get("name"))
		assert_eq(int(m.get("current_hp")), 1,
			"%s at 1 HP on the real load path" % m.get("name"))
