extends GutTest

## struktured 2026-08-15: "restarted game after dying from rat king and my
## entire party is KO'ed yet I'm walking around the dungeon."
## Mechanism: after a wipe the battle goes INACTIVE, the GameOverScreen is not
## a battle/interior/cutscene, so the 5-minute timed autosave passed
## can_quick_save() and snapshotted the dead party; Continue loaded it.
## Two floors: (1) no save path may capture a full wipe, (2) loading an
## already-poisoned save revives everyone at 1 HP so it is at least playable.

var _saved_party: Array[Dictionary] = []


func before_each() -> void:
	_saved_party = GameState.player_party.duplicate(true)


func after_each() -> void:
	GameState.player_party = _saved_party


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
