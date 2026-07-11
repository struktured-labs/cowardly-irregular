extends GutTest

## Regression suite for staged in-world cutscenes (presentation:"staged").
## Guards the load-bearing contracts:
##   1. Headless safety — every staged step resolves instantly with no live
##      stage/actor/camera (the story-spine walker executes all cutscene JSON
##      with no scene loaded; an unresolvable await = suite hang).
##   2. Skip contract — move_actor snaps to final position when _skipping.
##   3. Teardown placement — _end_staging() fires from _end_cutscene, NOT
##      from any mid-scene step (it landed inside _step_stop_timer once,
##      where a stop_timer step would have nuked all puppets mid-scene).
##   4. Staged scenes skip backdrop capture in BOTH entry points.
##   5. Choreography integrity — every actor id referenced in
##      world1_chapter1.json is spawned first; sheets resolve on disk.

const DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"
const ACTOR_PATH := "res://src/cutscene/CutsceneActor.gd"
const CHAPTER1_PATH := "res://data/cutscenes/world1_chapter1.json"

const _TOUCHED_FLAGS := ["cutscene_flag_staged_engine_test"]
var _saved_flags: Dictionary = {}
var _saved_current_map = null


func before_each() -> void:
	_saved_flags.clear()
	if GameState:
		for f in _TOUCHED_FLAGS:
			_saved_flags[f] = GameState.game_constants.get(f, null)
			GameState.game_constants.erase(f)
	_saved_current_map = MapSystem.current_map if MapSystem else null


func after_each() -> void:
	if GameState:
		for f in _TOUCHED_FLAGS:
			GameState.game_constants.erase(f)
			if _saved_flags.get(f) != null:
				GameState.game_constants[f] = _saved_flags[f]
	if MapSystem:
		MapSystem.current_map = _saved_current_map


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func _load_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(_read(path))
	assert_true(parsed is Dictionary, "%s must parse as a JSON object" % path)
	return parsed if parsed is Dictionary else {}


## Extract a function's body text (from its `func` line to the next top-level func).
func _func_body(source: String, func_name: String) -> String:
	var start = source.find("func %s(" % func_name)
	assert_true(start > -1, "function %s must exist in source" % func_name)
	var end = source.find("\nfunc ", start)
	return source.substr(start, (end - start) if end > -1 else -1)


func _new_director():
	var d = load(DIRECTOR_PATH).new()
	add_child_autofree(d)
	return d


## A minimal live stage for spawn/replace tests, torn down by autofree.
func _new_stage() -> Node2D:
	var stage := Node2D.new()
	add_child_autofree(stage)
	MapSystem.current_map = stage
	return stage


## =====================
## SOURCE-LEVEL PINS
## =====================

func test_end_staging_called_from_end_cutscene_not_steps() -> void:
	# Teardown must live in _end_cutscene; a mid-scene step calling it would
	# despawn every puppet mid-scene (this exact misplacement shipped once).
	var text = _read(DIRECTOR_PATH)
	assert_true(_func_body(text, "_end_cutscene").find("_end_staging()") > -1,
		"_end_cutscene must call _end_staging() — staged scenes otherwise leak puppets + hidden player")
	for step_func in ["_step_stop_timer", "_step_start_timer", "_step_set_flag"]:
		assert_false(_func_body(text, step_func).find("_end_staging()") > -1,
			"%s must NOT call _end_staging() — it would tear down puppets mid-scene" % step_func)


func test_both_entry_points_gate_backdrop_on_staged() -> void:
	# play_cutscene and play_cutscene_from_data have drifted before; both
	# must skip backdrop capture when presentation == "staged".
	var text = _read(DIRECTOR_PATH)
	for entry in ["play_cutscene", "play_cutscene_from_data"]:
		var body = _func_body(text, entry)
		assert_true(body.find("_begin_staging()") > -1,
			"%s must call _begin_staging() for staged scenes" % entry)
		var staged_idx = body.find("_begin_staging()")
		var backdrop_idx = body.find("_try_load_backdrop_image")
		assert_true(backdrop_idx > staged_idx,
			"%s: staged gate must run before (and branch around) backdrop capture" % entry)


## =====================
## CUTSCENE ACTOR CONTRACTS
## =====================

func test_actor_build_party_loads_artist_sheet() -> void:
	var a = CutsceneActor.build("t_fighter", {"kind": "party", "job": "fighter"})
	autofree(a)
	assert_eq(a._frames.size(), 16, "4x4 overworld sheet must slice into 16 frames")
	assert_true(a._frames["0_0"] is AtlasTexture, "party job sheet must load as atlas frames, not placeholder")


func test_actor_build_npc_archetype_loads_sheet() -> void:
	var a = CutsceneActor.build("t_scholar", {"kind": "npc", "archetype": "scholar"})
	autofree(a)
	assert_true(a._frames["0_0"] is AtlasTexture, "npc archetype sheet must load as atlas frames")


func test_actor_build_unknown_archetype_falls_back_to_placeholder() -> void:
	# A typo'd archetype must never crash a cutscene — placeholder instead.
	var a = CutsceneActor.build("t_bogus", {"kind": "npc", "archetype": "no_such_archetype_xyz"})
	autofree(a)
	assert_eq(a._frames.size(), 16, "placeholder must still fill all 16 frame slots")
	assert_false(a._frames["0_0"] is AtlasTexture, "unknown archetype must use the placeholder texture")


func test_actor_facing_rows_match_sheet_order() -> void:
	# Sheet row order is down/left/right/up (WanderingNPC layout). OverworldNPC's
	# facing enum differs — copying it garbles every walk animation.
	var a = CutsceneActor.build("t_face", {"kind": "party", "job": "fighter"})
	autofree(a)
	a.set_facing_name("down")
	assert_eq(a._facing, 0, "down must be sheet row 0")
	a.set_facing_name("left")
	assert_eq(a._facing, 1, "left must be sheet row 1")
	a.set_facing_name("right")
	assert_eq(a._facing, 2, "right must be sheet row 2")
	a.set_facing_name("up")
	assert_eq(a._facing, 3, "up must be sheet row 3")


func test_actor_walk_to_off_tree_snaps_instantly() -> void:
	# Headless contract: an actor not in the tree cannot tween — walk_to
	# must snap and return without awaiting (spine-walker hang otherwise).
	var a = CutsceneActor.build("t_walk", {"kind": "party", "job": "fighter"})
	await a.walk_to(Vector2(500, 300))
	assert_eq(a.position, Vector2(500, 300), "off-tree walk_to must snap to target instantly")
	a.free()


func test_actor_hop_off_tree_returns_instantly() -> void:
	var a = CutsceneActor.build("t_hop", {"kind": "party", "job": "fighter"})
	await a.hop(2)
	assert_true(true, "off-tree hop must return without awaiting")
	a.free()


func test_actor_emote_glyphs_are_monochrome_unicode() -> void:
	# No emoji font fallback exists — color emoji render as tofu boxes.
	for kind in CutsceneActor.EMOTE_GLYPHS:
		var glyph: String = CutsceneActor.EMOTE_GLYPHS[kind]
		for i in glyph.length():
			assert_true(glyph.unicode_at(i) < 0x2700,
				"emote glyph '%s' (%s) must stay monochrome-safe Unicode, not emoji" % [glyph, kind])


## =====================
## DIRECTOR STAGED HANDLERS (behavioral)
## =====================

func test_spawn_actor_registers_puppet_on_live_stage() -> void:
	var stage := _new_stage()
	var d = _new_director()
	d._step_spawn_actor({"id": "hero", "kind": "party", "job": "fighter", "at": [100, 200]})
	var a = d._actors.get("hero")
	assert_not_null(a, "spawn_actor must register the puppet in _actors")
	assert_eq(a.get_parent(), stage, "puppet must parent into the live map, never the director CanvasLayer")
	assert_eq(a.global_position, Vector2(100, 200), "puppet must spawn at the 'at' mark")


func test_spawn_actor_without_stage_is_headless_noop() -> void:
	MapSystem.current_map = null
	var d = _new_director()
	d._step_spawn_actor({"id": "ghost", "kind": "party", "job": "fighter", "at": [10, 10]})
	assert_false(d._actors.has("ghost"), "no live stage → spawn_actor must no-op (headless walker safety)")


func test_replace_npc_hides_live_npc_and_inherits_position() -> void:
	var stage := _new_stage()
	var npc := OverworldNPC.new()
	npc.npc_name = "Elder Theron"
	stage.add_child(npc)
	npc.position = Vector2(256, 192)
	var d = _new_director()
	d._step_spawn_actor({"id": "elder", "kind": "npc", "archetype": "old_man", "replace_npc": "Elder Theron"})
	assert_false(npc.visible, "replace_npc must hide the live NPC for the scene")
	var a = d._actors.get("elder")
	assert_not_null(a, "puppet must spawn")
	assert_eq(a.global_position, Vector2(256, 192), "puppet must inherit the replaced NPC's position")
	d._end_staging()
	assert_true(npc.visible, "_end_staging must restore the replaced NPC's visibility")
	assert_true(d._actors.is_empty(), "_end_staging must clear the actor registry")


func test_begin_staging_hides_player_and_end_staging_restores() -> void:
	var player := Node2D.new()
	player.add_to_group("player")
	add_child_autofree(player)
	var d = _new_director()
	d._begin_staging()
	assert_false(player.visible, "_begin_staging must hide the real player (puppets own the frame)")
	d._end_staging()
	assert_true(player.visible, "_end_staging must restore the real player")


func test_move_actor_snaps_when_skipping() -> void:
	# Skip contract: hold-B must snap actors to final marks, never tween.
	var _stage := _new_stage()
	var d = _new_director()
	d._step_spawn_actor({"id": "hero", "kind": "party", "job": "fighter", "at": [0, 0]})
	d._skipping = true
	await d._step_move_actor({"id": "hero", "to": [400, 352]})
	assert_eq(d._actors["hero"].global_position, Vector2(400, 352),
		"move_actor under _skipping must snap to the final mark instantly")


func test_move_actor_unknown_id_resolves_instantly() -> void:
	var d = _new_director()
	await d._step_move_actor({"id": "nobody", "to": [50, 50]})
	assert_true(true, "unknown actor id must resolve instantly, never await")


func test_staged_minimal_playthrough_headless_sets_flag() -> void:
	# End-to-end: a staged cutscene with every new step type completes
	# headless (no stage, no camera) and still lands its set_flag.
	MapSystem.current_map = null
	var d = _new_director()
	var data := {
		"presentation": "staged",
		"steps": [
			{"type": "spawn_actor", "id": "a", "kind": "party", "job": "fighter", "at": [0, 0]},
			{"type": "move_actor", "id": "a", "to": [64, 0]},
			{"type": "face_actor", "id": "a", "dir": "left"},
			{"type": "emote", "id": "a", "emote": "exclaim", "duration": 0.2},
			{"type": "hop", "id": "a", "times": 1},
			{"type": "camera_focus", "target": "a", "duration": 0.2},
			{"type": "set_flag", "flag": "staged_engine_test", "value": true},
			{"type": "camera_restore", "duration": 0.2},
			{"type": "despawn_actor", "id": "a"},
		],
	}
	await d.play_cutscene_from_data("staged_engine_test_scene", data)
	assert_true(GameState.game_constants.get("cutscene_flag_staged_engine_test", false),
		"staged playthrough must complete headless and land its set_flag")
	assert_false(d._staged, "_end_cutscene must reset _staged")
	assert_true(d._actors.is_empty(), "no puppets may leak past _end_cutscene")


## =====================
## CONTENT PINS (world1_chapter1 + all staged scenes)
## =====================

func test_chapter1_is_staged_and_keeps_completion_flag() -> void:
	var data := _load_json(CHAPTER1_PATH)
	assert_eq(str(data.get("presentation", "")), "staged", "world1_chapter1 is the staged-mode proof scene")
	var found_flag := false
	for step in data.get("steps", []):
		if str(step.get("type")) == "set_flag" and str(step.get("flag")) == "chapter1_complete":
			found_flag = true
	assert_true(found_flag,
		"chapter1_complete set_flag must survive re-staging — it pairs with _CUTSCENE_COMPLETION_FLAGS (Elder Theron loop bug)")


func test_staged_scenes_reference_only_spawned_actor_ids() -> void:
	# Choreography integrity for EVERY staged cutscene: a typo'd actor id
	# silently no-ops (headless-safe by design), so pin it at content level.
	for path in _staged_cutscene_paths():
		var data := _load_json(path)
		var spawned := {}
		for step in data.get("steps", []):
			var t := str(step.get("type", ""))
			match t:
				"spawn_actor":
					spawned[str(step.get("id"))] = true
				"despawn_actor", "move_actor", "face_actor", "emote", "hop":
					assert_true(spawned.has(str(step.get("id"))),
						"%s: %s references unspawned actor '%s'" % [path, t, step.get("id")])
					if t == "face_actor" and step.has("toward"):
						assert_true(spawned.has(str(step.get("toward"))),
							"%s: face_actor toward unspawned actor '%s'" % [path, step.get("toward")])
				"camera_focus":
					var target = step.get("target")
					if target is String:
						assert_true(spawned.has(target),
							"%s: camera_focus targets unspawned actor '%s'" % [path, target])


func test_staged_scene_actor_sheets_exist_on_disk() -> void:
	# Every spawn_actor's sheet must resolve; a missing sheet ships a
	# purple placeholder box into a story scene (silent failure class).
	for path in _staged_cutscene_paths():
		var data := _load_json(path)
		for step in data.get("steps", []):
			if str(step.get("type", "")) != "spawn_actor":
				continue
			var sheet: String
			if str(step.get("kind", "npc")) == "party":
				sheet = "res://assets/sprites/jobs/%s/overworld.png" % str(step.get("job", ""))
			else:
				sheet = "res://assets/sprites/npcs/%s/overworld.png" % str(step.get("archetype", ""))
			assert_true(ResourceLoader.exists(sheet),
				"%s: spawn_actor '%s' needs sheet %s" % [path, step.get("id"), sheet])


func _staged_cutscene_paths() -> Array:
	var paths: Array = []
	var dir = DirAccess.open("res://data/cutscenes")
	assert_not_null(dir, "cutscenes dir must open")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var p = "res://data/cutscenes/%s" % f
		if _read(p).find("\"presentation\": \"staged\"") > -1:
			paths.append(p)
	assert_true(paths.size() >= 1, "at least world1_chapter1 must be staged")
	return paths


## =====================
## LIVE-NPC / PUPPET LOOK CONSISTENCY
## =====================

## Canonical archetype per Harmonia story NPC. Live map AND staged puppets
## must both resolve to these — the name-hash fallback once rendered Theron
## as old_woman and Phil as young_woman, so puppets visibly transformed the
## NPC at scene start. Now the named sheets from 2fd985bb.
const HARMONIA_NPC_CANON := {
	"Elder Theron": "elder_theron",
	"Scholar Milo": "scholar_milo",
	"Phil the Lost": "phil",
	"Bram Smith": "bram",
}


func test_harmonia_story_npcs_resolve_canon_archetypes() -> void:
	var packed: PackedScene = load("res://src/maps/villages/HarmoniaVillage.tscn")
	assert_not_null(packed, "HarmoniaVillage scene must load")
	var scene: Node = packed.instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var found := {}
	_collect_named_npcs(scene, found)
	for npc_name in HARMONIA_NPC_CANON:
		var npc = found.get(npc_name)
		assert_not_null(npc, "Harmonia must contain NPC '%s'" % npc_name)
		if npc == null:
			continue
		assert_eq(npc._resolve_archetype(), HARMONIA_NPC_CANON[npc_name],
			"'%s' must resolve archetype '%s' on the live map (hash fallback drifted from story canon before)" % [npc_name, HARMONIA_NPC_CANON[npc_name]])


func test_staged_puppets_match_live_npc_archetypes() -> void:
	# replace_npc swaps live NPC → puppet mid-frame; differing sheets read
	# as the character transforming. Pin puppet archetype == live canon.
	for path in _staged_cutscene_paths():
		var data := _load_json(path)
		for step in data.get("steps", []):
			if str(step.get("type", "")) != "spawn_actor":
				continue
			var replaced := str(step.get("replace_npc", ""))
			if replaced == "" or not HARMONIA_NPC_CANON.has(replaced):
				continue
			assert_eq(str(step.get("archetype", "")), HARMONIA_NPC_CANON[replaced],
				"%s: puppet for '%s' must use live-map archetype '%s'" % [path, replaced, HARMONIA_NPC_CANON[replaced]])


func _collect_named_npcs(root: Node, out: Dictionary) -> void:
	for child in root.get_children():
		if "npc_name" in child and child.has_method("_resolve_archetype"):
			out[str(child.npc_name)] = child
		_collect_named_npcs(child, out)
