extends GutTest

## cowir-main 2026-11-04, from the real-battle signature clips: every scripted boss fought on the same generic "boss"
## backdrop, because GameLoop's boss branch forced set_terrain("boss"). A boss now fights in its own dungeon: its
## monsters.json `boss_terrain`, else "boss". The terrain must be one the background actually understands.

const BG_PATH := "res://src/battle/BattleBackground.gd"
const GameLoopScript := preload("res://src/GameLoop.gd")
const W1 := ["cave_rat_king", "fire_dragon", "ice_dragon", "lightning_dragon", "shadow_dragon", "chancellor_mordaine"]


## Every terrain name BattleBackground.set_terrain_from_string matches, read from its own source.
func _known_terrains() -> Array:
	var src := FileAccess.get_file_as_string(BG_PATH)
	var at := src.find("func set_terrain_from_string")
	var body := src.substr(at, src.find("\nfunc ", at + 10) - at) if at >= 0 else ""
	var out: Array = []
	var re := RegEx.create_from_string("\"([a-z_]+)\"")
	for m in re.search_all(body):
		out.append(m.get_string(1))
	return out


func test_every_w1_boss_resolves_to_a_terrain_that_exists() -> void:
	var known := _known_terrains()
	assert_true("cave" in known and "boss" in known and "volcanic" in known, "CONTROL: the terrain list was read (%s)" % str(known))
	var monsters = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	for id in W1:
		var authored := str(monsters[id].get("boss_terrain", ""))
		assert_ne(authored, "", "%s names its own battleground" % id)
		var t: String = GameLoopScript.boss_terrain_for([id])
		assert_eq(t, authored, "%s fights on its own boss_terrain" % id)
		assert_true(t in known, "%s's terrain '%s' is one the background understands" % [id, t])


func test_a_boss_without_one_keeps_the_shared_arena() -> void:
	assert_eq(GameLoopScript.boss_terrain_for(["goblin"]), "boss", "no boss_terrain → the shared boss backdrop")
	assert_eq(GameLoopScript.boss_terrain_for([]), "boss", "and no enemies at all → the same")


## The scripted-boss branch must ASK, not force: a source pin, since driving a whole boss start here is a GameLoop boot.
func test_the_boss_branch_asks_for_the_terrain() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var at := src.find("battle_scene.forced_enemies = enemy_ids")
	assert_gt(at, 0, "CONTROL: the boss branch is where it was")
	var branch := src.substr(at, 300)
	assert_true(branch.contains("set_terrain(boss_terrain_for(enemy_ids))"), "the boss branch reads the boss's own terrain")
	assert_false(branch.contains("set_terrain(\"boss\")"), "and no longer forces the shared one")
