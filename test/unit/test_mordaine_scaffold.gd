extends GutTest

## Tests for the Mordaine boss scaffold (2026-05-23).
##
## Mordaine is the narratively-foundational W1 antagonist (referenced
## across all 6 worlds' cutscenes) but was previously not implementable
## as a fightable boss. This scaffold adds:
##   - monsters.json entry `chancellor_mordaine`
##   - CastleHarmonia.gd scene (extends DragonCave, single-floor arena)
##   - GameLoop transition wire-up for "castle_harmonia" map_id
##   - TeleportMenu entry for debug access
##
## When Mordaine is defeated the `world1_mordaine_defeated` flag gets
## set via the standard DragonCave pending_boss_defeat machinery,
## which then gates the W2 prologue cutscene.


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_chancellor_mordaine_exists_in_monsters_json() -> void:
	var data = JSON.parse_string(_read("res://data/monsters.json"))
	assert_not_null(data, "monsters.json must parse")
	assert_true(data.has("chancellor_mordaine"),
		"monsters.json must define chancellor_mordaine (regression: W1 final boss must be fightable)")


func test_mordaine_has_required_stats_block() -> void:
	var data = JSON.parse_string(_read("res://data/monsters.json"))
	var m = data["chancellor_mordaine"]
	# Sanity check the stat block — without these the battle engine spawns
	# a 0-HP, 0-stat phantom that dies on the first attack and unlocks W2
	# in 50ms. Asserting realistic minimums protects the design intent.
	assert_eq(m.get("boss", false), true, "must be tagged boss")
	assert_gt(m.get("level", 0), 18,
		"Mordaine must be at least LV 19 (above shadow_dragon LV 18, the W1 elemental cap)")
	var stats = m.get("stats", {})
	assert_gt(stats.get("max_hp", 0), 1000,
		"Mordaine HP must exceed 1000 (regression: scrub stats let her die instantly)")
	assert_gt(stats.get("magic", 0), 50,
		"Mordaine is magic-heavy (sorceress-usurper) — magic stat must dominate")


func test_mordaine_uses_existing_intro_cutscene() -> void:
	# The intro cutscene world1_mordaine_intro.json is the load-bearing
	# narrative entry. If CastleHarmonia points to a different cutscene
	# id, the throne-room confrontation never plays.
	var castle_src = _read("res://src/maps/dungeons/CastleHarmonia.gd")
	assert_true(castle_src.find('"world1_mordaine_intro"') != -1,
		"CastleHarmonia must reference world1_mordaine_intro cutscene id")
	# Confirm the cutscene file still exists at the expected path.
	var cs_path = "res://data/cutscenes/world1_mordaine_intro.json"
	assert_true(FileAccess.file_exists(cs_path),
		"world1_mordaine_intro.json must exist at %s (regression: cutscene removal would break boss intro)" % cs_path)


func test_mordaine_defeat_sets_w1_completion_flag() -> void:
	# Source-level: CastleHarmonia must set boss_flag_key to the same
	# flag _get_pending_story_cutscene checks for the W2 prologue trigger.
	# (cutscene_flag_world1_mordaine_defeated gates "world2_prologue".)
	var castle_src = _read("res://src/maps/dungeons/CastleHarmonia.gd")
	assert_true(castle_src.find("world1_mordaine_defeated") != -1,
		"CastleHarmonia must set boss_flag_key to world1_mordaine_defeated")
	# Sanity: GameLoop._get_pending_story_cutscene still gates on this flag.
	var gameloop_src = _read("res://src/GameLoop.gd")
	assert_true(gameloop_src.find("cutscene_flag_world1_mordaine_defeated") != -1,
		"GameLoop must still gate W2 prologue on cutscene_flag_world1_mordaine_defeated")


func test_castle_harmonia_registered_in_gameloop_map_switch() -> void:
	# Without this entry the "castle_harmonia" map_id falls through to the
	# default branch and the scene never instantiates — TeleportMenu would
	# warp the player into a black void.
	var gameloop_src = _read("res://src/GameLoop.gd")
	assert_true(gameloop_src.find('"castle_harmonia"') != -1,
		"GameLoop must have a 'castle_harmonia' case in the map-switch (regression: teleport into void)")
	assert_true(gameloop_src.find("CastleHarmoniaScript") != -1,
		"GameLoop must preload CastleHarmoniaScript")


func test_castle_harmonia_in_teleport_menu() -> void:
	# Debug-mode players need a way to reach the arena before the
	# overworld placement is decided. Removing this entry early would
	# strand Mordaine playtesting until the overworld portal is wired.
	var menu_src = _read("res://src/ui/TeleportMenu.gd")
	assert_true(menu_src.find('"castle_harmonia"') != -1,
		"TeleportMenu must list castle_harmonia for debug access")


func test_castle_harmonia_extends_dragon_cave_with_single_floor() -> void:
	# Mordaine is a single-room throne confrontation, not a multi-floor
	# dungeon crawl. Setting total_floors=1 means the down-stairs `D`
	# on floor 1 exits the castle directly rather than descending.
	var castle_src = _read("res://src/maps/dungeons/CastleHarmonia.gd")
	assert_true(castle_src.find("extends DragonCave") != -1,
		"CastleHarmonia should extend DragonCave for free boss-trigger/cutscene/flag wiring")
	assert_true(castle_src.find("total_floors = 1") != -1,
		"CastleHarmonia should be single-floor (boss arena, not dungeon crawl)")


func test_mordaine_unlocks_world_2() -> void:
	# Per the lore + cutscene flow, defeating Mordaine should unlock W2.
	# The DragonCave base sets unlock_world via pending_boss_defeat.
	var castle_src = _read("res://src/maps/dungeons/CastleHarmonia.gd")
	assert_true(castle_src.find("unlock_world = 2") != -1,
		"CastleHarmonia must set unlock_world = 2 (Mordaine's defeat is the W1→W2 gate)")
