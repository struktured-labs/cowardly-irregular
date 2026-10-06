extends GutTest

## Regression (struktured's 2026-10-05 logs): a pre-2026-07-29 save in slot 2 logged "migrated 5 party member(s) to
## stat scale x10" four times per session, because the title's slot list re-reads every file. It is reported once
## per slot per session now; the migration itself still runs on every read, since the file on disk is unchanged.


func before_each() -> void:
	SaveSystem._migration_reported.clear()


func after_each() -> void:
	SaveSystem._migration_reported.clear()


func _old_save() -> Dictionary:
	return {"game_state": {"player_party": [{"name": "Fighter", "max_hp": 100, "current_hp": 100, "attack": 20}]}}


func test_the_second_read_still_migrates() -> void:
	var a: Dictionary = SaveSystem._migrate_stat_denomination(_old_save(), 2)
	var b: Dictionary = SaveSystem._migrate_stat_denomination(_old_save(), 2)
	assert_eq(int(a["game_state"]["player_party"][0]["max_hp"]), 100 * Combatant.STAT_SCALE, "SCOPE: the first read migrates")
	assert_eq(int(b["game_state"]["player_party"][0]["max_hp"]), 100 * Combatant.STAT_SCALE, "a quiet re-read must still migrate the stats")


func test_a_slot_is_reported_once() -> void:
	SaveSystem._migrate_stat_denomination(_old_save(), 2)
	assert_true(SaveSystem._migration_reported.has(2), "the first migration of slot 2 is reported and remembered")
	assert_eq(SaveSystem._migration_reported.size(), 1, "CONTROL: only the slot that migrated is marked")


func test_a_current_save_marks_nothing() -> void:
	var cur := {"game_state": {"player_party": [{"name": "F", "max_hp": 1000, "stat_scale": Combatant.STAT_SCALE}]}}
	SaveSystem._migrate_stat_denomination(cur, 3)
	assert_false(SaveSystem._migration_reported.has(3), "CONTROL: a save already at scale reports nothing")
