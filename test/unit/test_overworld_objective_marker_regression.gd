extends GutTest

## Regression test for the overworld minimap/arrow objective marker bug
## (2026-06-14).
##
## Bug: OverworldScene._get_objective_position() decided the "go to cave"
## guidance marker with `gs.get_story_flag("chapter1_complete")`. But
## chapter1_complete is never written to story_flags — the chapter1 (Elder
## Theron) cutscene completion only ever sets
## GameState.game_constants["cutscene_flag_chapter1_complete"] = true
## (GameLoop._play_story_cutscene via _CUTSCENE_COMPLETION_FLAGS).
## get_story_flag reads ONLY story_flags, so the check stayed false forever
## and the minimap/ObjectiveArrow kept pointing at the village entrance
## instead of the Whispering Cave. The marker only corrected itself once
## rat_king_defeated / w1_boss_defeated landed in story_flags — i.e. AFTER
## the player had already found and cleared the cave, defeating the point
## of the guidance.
##
## Fix: dual-namespace check, same guard QuestTracker.gd already uses —
##   gs.get_story_flag("chapter1_complete")
##     or gs.game_constants.get("cutscene_flag_chapter1_complete", false)
##
## This file owns OverworldScene._get_objective_position behavior end-to-end
## by exercising a real instance against the live GameState autoload.

const OverworldSceneScript = preload("res://src/exploration/OverworldScene.gd")

var _saved_story_flags: Dictionary = {}
var _saved_chapter1_const = null
var _had_chapter1_const: bool = false


func before_each() -> void:
	# Snapshot the live GameState autoload so we can restore it after each test.
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs == null:
		return
	_saved_story_flags = gs.story_flags.duplicate(true)
	_had_chapter1_const = gs.game_constants.has("cutscene_flag_chapter1_complete")
	_saved_chapter1_const = gs.game_constants.get("cutscene_flag_chapter1_complete", null)
	# Start from a clean slate so prior tests / save state don't leak in.
	gs.story_flags.erase("chapter1_complete")
	gs.story_flags.erase("rat_king_defeated")
	gs.story_flags.erase("w1_boss_defeated")  # legacy cleanup; tick 278 swapped to the cutscene_flag form
	gs.game_constants.erase("cutscene_flag_world1_mordaine_defeated")
	gs.game_constants.erase("cutscene_flag_chapter1_complete")


func after_each() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs == null:
		return
	gs.story_flags = _saved_story_flags.duplicate(true)
	if _had_chapter1_const:
		gs.game_constants["cutscene_flag_chapter1_complete"] = _saved_chapter1_const
	else:
		gs.game_constants.erase("cutscene_flag_chapter1_complete")


func _make_scene() -> OverworldScene:
	# Full _ready() populates spawn_points (cave_entrance, village_entrance,
	# steampunk_portal) and puts the node in the tree so _get_game_state()
	# can resolve the GameState autoload — matching test_overworld_encounters.
	var scene = OverworldSceneScript.new()
	add_child_autofree(scene)
	await get_tree().process_frame
	return scene


func test_marker_points_at_cave_when_only_game_constant_flag_set() -> void:
	# Core regression: chapter1 cutscene done, but the flag exists ONLY as
	# game_constants["cutscene_flag_chapter1_complete"] (never in story_flags).
	# The marker MUST point at the cave, not the village.
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs == null:
		pass_test("GameState autoload unavailable; skipping")
		return
	gs.game_constants["cutscene_flag_chapter1_complete"] = true

	var scene = await _make_scene()
	var cave = scene.spawn_points.get("cave_entrance", Vector2.ZERO)
	var village = scene.spawn_points.get("village_entrance", Vector2.ZERO)
	assert_ne(cave, Vector2.ZERO, "cave_entrance spawn point should exist")
	assert_ne(cave, village, "cave and village spawn points should differ (precondition)")

	var objective = scene._get_objective_position()
	assert_eq(objective, cave,
		"After chapter1 cutscene (cutscene_flag_chapter1_complete in game_constants), " +
		"objective marker must point at the cave, not the village. " +
		"Got %s, cave=%s, village=%s" % [objective, cave, village])


func test_marker_points_at_village_before_chapter1() -> void:
	# Before chapter1 is complete in EITHER namespace, the marker should fall
	# through to the village entrance (the introductory objective).
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs == null:
		pass_test("GameState autoload unavailable; skipping")
		return

	var scene = await _make_scene()
	var village = scene.spawn_points.get("village_entrance", Vector2.ZERO)
	var objective = scene._get_objective_position()
	assert_eq(objective, village,
		"With no chapter1/rat_king/boss flags set, marker should point at the village. " +
		"Got %s, village=%s" % [objective, village])


func test_marker_still_points_at_cave_via_story_flag() -> void:
	# Backward-compat: if chapter1_complete is ever set the "old" way (in
	# story_flags directly), the marker must still point at the cave.
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs == null:
		pass_test("GameState autoload unavailable; skipping")
		return
	gs.story_flags["chapter1_complete"] = true

	var scene = await _make_scene()
	var cave = scene.spawn_points.get("cave_entrance", Vector2.ZERO)
	var objective = scene._get_objective_position()
	assert_eq(objective, cave,
		"chapter1_complete set in story_flags should still route marker to the cave. " +
		"Got %s, cave=%s" % [objective, cave])


func test_marker_points_at_portal_after_boss() -> void:
	# Once the W1 boss (Mordaine) is down, the objective advances to the
	# world portal. Tick 278: was reading dead story_flag
	# "w1_boss_defeated" (no writer in src/) — replaced with the real
	# cutscene_flag_world1_mordaine_defeated set by CastleHarmonia's
	# defeat_cutscene_flags ratchet.
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs == null:
		pass_test("GameState autoload unavailable; skipping")
		return
	gs.game_constants["cutscene_flag_world1_mordaine_defeated"] = true
	# Even with the chapter1 game_constant set, boss-defeated takes priority.
	gs.game_constants["cutscene_flag_chapter1_complete"] = true

	var scene = await _make_scene()
	var portal = scene.spawn_points.get("steampunk_portal", Vector2.ZERO)
	var objective = scene._get_objective_position()
	assert_eq(objective, portal,
		"After Mordaine defeat, marker should point at the world portal. " +
		"Got %s, portal=%s" % [objective, portal])


func test_get_objective_position_reads_both_namespaces() -> void:
	# Source-level guard: the dual-namespace check must be present so a future
	# edit can't silently regress back to the bare get_story_flag path.
	var file = FileAccess.open("res://src/exploration/OverworldScene.gd", FileAccess.READ)
	assert_not_null(file, "OverworldScene.gd should be readable")
	var text = file.get_as_text()
	file.close()
	var idx = text.find("func _get_objective_position")
	assert_gt(idx, -1, "_get_objective_position must exist")
	var next_func = text.find("\nfunc ", idx + 1)
	if next_func == -1:
		next_func = text.length()
	var body = text.substr(idx, next_func - idx)
	assert_true(body.find("cutscene_flag_chapter1_complete") != -1,
		"_get_objective_position must consult game_constants[\"cutscene_flag_chapter1_complete\"] " +
		"(regression: chapter1_complete lives there, never in story_flags)")
