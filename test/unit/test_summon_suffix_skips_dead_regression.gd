extends GutTest

## History of the summon-letter rule, because it has flipped once and the reason matters:
## 2026-07-03: only ALIVE same-type enemies held a letter, so a roster never read "A, C, D" after a kill.
## 2026-10-31, struktured's .754 play: the enemy panel KEEPS defeated enemies listed ("Goblin A ✗ DEFEATED"),
## so a summon taking the dead letter showed two "Goblin A" rows, one dead and one alive. A duplicate name
## on screen is worse than a gap in the letters. Every enemy on the field now holds its letter, dead or alive
## (BattleScene.summon_names_taken). The file name is kept so its history stays findable.

const BATTLE_SCENE_PATH := "res://src/battle/BattleScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_a_defeated_enemy_keeps_its_letter() -> void:
	var BS = load(BATTLE_SCENE_PATH)
	var dead := Combatant.new()
	autofree(dead)
	dead.combatant_name = "Goblin A"
	dead.is_alive = false
	var live := Combatant.new()
	autofree(live)
	live.combatant_name = "Goblin C"
	live.is_alive = true
	var taken: Array = BS.summon_names_taken([dead, live])
	assert_true("Goblin A" in taken, "a DEFEATED goblin still holds its letter; the panel still shows its row")
	assert_eq(BS.pick_summon_name("Goblin", taken), "Goblin B",
		"the summon takes the first letter nobody on the field has, alive or dead")


func test_a_freed_entry_is_skipped_not_fatal() -> void:
	var BS = load(BATTLE_SCENE_PATH)
	var gone := Combatant.new()
	gone.combatant_name = "Goblin A"
	gone.free()
	assert_eq(BS.summon_names_taken([gone]), [], "a freed combatant names nothing and must not abort the count")


func test_the_summon_path_names_from_the_whole_field() -> void:
	var text := _read(BATTLE_SCENE_PATH)
	var fn := text.substr(text.find("func _on_monster_summoned"), 1200)
	assert_true(fn.contains("pick_summon_name(str(monster_data[\"name\"]), summon_names_taken(test_enemies))"),
		"_on_monster_summoned must pick from every enemy's name, not a living-only list")
