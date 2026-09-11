extends GutTest

## tick 95 regression: W2-W5 dungeons must declare defeat_cutscene
## pointing to a real defeat cutscene JSON. Pre-fix, the W2-W5
## dungeons (SuburbanUnderground, SteampunkMechanism, AssemblyCore,
## RootProcess) declared boss_cutscene_id (intro) but NOT
## defeat_cutscene — so on victory, DragonCave._on_boss_defeated
## skipped the defeat cutscene play entirely (line 543 guards on
## `defeat_cutscene != ""`).
##
## The defeat cutscene files all existed in data/cutscenes/, just
## never reached: world2_warden_defeat / world3_tempo_defeat /
## world4_warden_defeat / world5_arbiter_defeat. Players got the
## boss intro but no post-victory dialogue.
##
## 2026-09-11: the cutscene IDs below moved. These lists pinned "a defeat cutscene
## is wired", never "the defeat cutscene belongs to the boss you just beat" — and
## two of them did not. AssemblyCore's boss is the Warden of the Assembly Line and
## played the FUTURISTIC Warden's aftermath; RootProcess's boss is the Arbiter of
## the Benchmark and played the ABSTRACT Arbiter's. The masterite aftermath scenes
## are filed one world below the boss they belong to. test_defeat_cutscene_names_
## the_boss_that_triggered_it_regression.gd is the arm that checks ownership; this
## file stays the reachability arm and the two are deliberately separate.
##
## W6 NullChamber skipped: world6_curator_defeat.json doesn't exist
## on disk yet (the only authored W6 boss-defeat cutscene is the
## final Calibrant battle, not the NullChamber dungeon Curator).

const DUNGEON_DEFEATS: Array[Array] = [
	["res://src/maps/dungeons/SuburbanUnderground.gd",  "world2_warden_defeat"],
	["res://src/maps/dungeons/SteampunkMechanism.gd",   "world3_grand_schedule_defeat"],  # 2026-09-11: W3's boss is The Grand Schedule (masterite_tempo_steampunk); the world3_tempo_* pair belongs to W4's industrial Tempo by trigger
	["res://src/maps/dungeons/AssemblyCore.gd",         "world3_warden_defeat"],
	["res://src/maps/dungeons/RootProcess.gd",          "world4_arbiter_defeat"],
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_every_w2_w5_dungeon_defeat_cutscene_reachable_via_game_loop() -> void:
	# Tick 105: the original assertion was "each dungeon declares
	# defeat_cutscene = '<id>'". That field was removed as dead code
	# (read only by DragonCave._on_boss_defeated which had no caller).
	# The replacement mechanism is GameLoop._get_pending_story_cutscene
	# gates — pin THAT instead so the live mechanism is checked.
	var game_loop := _read("res://src/GameLoop.gd")
	for entry in DUNGEON_DEFEATS:
		var expected: String = entry[1]
		assert_true(game_loop.contains("return \"" + expected + "\""),
			"GameLoop._get_pending_story_cutscene must return '%s' — the post-tick-105 mechanism that replaces the removed defeat_cutscene field" % expected)


func test_every_referenced_defeat_cutscene_file_exists() -> void:
	for entry in DUNGEON_DEFEATS:
		var expected: String = entry[1]
		var path: String = "res://data/cutscenes/" + expected + ".json"
		assert_true(FileAccess.file_exists(path),
			"Defeat cutscene file %s must exist on disk" % path)


func test_w6_null_chamber_defeat_cutscene_not_yet_authored() -> void:
	# Negative pin documenting why W6 is excluded: the Curator
	# defeat cutscene file doesn't exist yet. If a future commit
	# authors it AND wires NullChamber, this test should be removed
	# and that entry added to DUNGEON_DEFEATS above.
	assert_false(FileAccess.file_exists("res://data/cutscenes/world6_curator_defeat.json"),
		"If world6_curator_defeat.json now exists, wire NullChamber.defeat_cutscene and remove this guard")


func test_w1_castle_harmonia_defeat_cutscene_now_reachable_via_game_loop() -> void:
	# Tick 105: CastleHarmonia's `defeat_cutscene = "world1_mordaine_defeat"`
	# field assignment was removed (dead code). The Mordaine post-defeat
	# dialogue now plays via the GameLoop gate added in tick 104.
	var src := _read("res://src/GameLoop.gd")
	assert_true(src.contains("return \"world1_mordaine_defeat\""),
		"GameLoop must gate world1_mordaine_defeat in _get_pending_story_cutscene — the post-tick-105 mechanism that replaces CastleHarmonia's removed defeat_cutscene field")


func test_dragon_cave_no_longer_has_dead_defeat_cutscene_path() -> void:
	# Tick 105: removed _on_boss_defeated function + defeat_cutscene field
	# from DragonCave. They were pure dead code (no caller anywhere).
	# Pin the negative so a future revert is caught.
	var src := _read("res://src/maps/dungeons/DragonCave.gd")
	assert_false(src.contains("var defeat_cutscene: String"),
		"DragonCave must NOT declare `var defeat_cutscene: String` — removed as dead code")
	assert_false(src.contains("func _on_boss_defeated()"),
		"DragonCave must NOT define _on_boss_defeated — removed as dead code (no caller existed)")
