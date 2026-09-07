extends GutTest

## `conscript_nearby` — struktured's staging v2 idea (msg 2392, verbatim):
## "or they can move the npcs around as puppets too which are likely to be
## close by the scene!"
##
## Pre-fix, _begin_staging HID every live NPC in the stage so puppets owned
## the frame (msg 2388 fix — ambient villagers loitered inside the blocking).
## Correct, but it empties a village square that should feel populated.
##
## With the feature on, in-radius NPCs are still hidden — but a CutsceneActor
## is spawned in each one's place, wearing that NPC's own archetype, so the
## crowd stays present AND becomes directable. Authors drive them with
## nearby_face / nearby_scatter without knowing who happens to be standing
## there (wanderers move; the roster isn't static).
##
## Contract pinned here:
##   1. OFF BY DEFAULT — a scene with no `conscript_nearby` root field keeps
##      the exact pre-2026-07-25 hide-only behavior. Both shipped staged
##      scenes rely on that.
##   2. Ids are deterministic (nearest-first) so a scene authored against
##      nearby_1 means the same actor on every run.
##   3. Radius and max are honored — a crowded village can't spawn 20 puppets.
##   4. Conscripts inherit the replaced NPC's archetype, not a generic.
##   5. Headless-safe — no stage, no player, or no NPCs = clean no-op.
##   6. Teardown clears conscript state (leak guard for the next scene).

const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _new_director():
	var d = load(DIRECTOR).new()
	add_child_autofree(d)
	return d


func _new_stage() -> Node2D:
	var stage := Node2D.new()
	add_child_autofree(stage)
	if MapSystem:
		MapSystem.current_map = stage
	return stage


func _add_npc(stage: Node2D, npc_name: String, pos: Vector2, archetype: String = "") -> OverworldNPC:
	var npc := OverworldNPC.new()
	npc.npc_name = npc_name
	if archetype != "":
		npc.sprite_archetype = archetype
	stage.add_child(npc)
	npc.global_position = pos
	return npc


var _saved_map = null


func before_each() -> void:
	_saved_map = MapSystem.current_map if MapSystem else null


func after_each() -> void:
	if MapSystem:
		MapSystem.current_map = _saved_map


# ── Contract 1: off by default ────────────────────────────────────────

func test_absent_field_keeps_hide_only_behavior() -> void:
	var stage := _new_stage()
	_add_npc(stage, "Villager A", Vector2(10, 10))
	var d = _new_director()
	d._conscript_spec = {}   # what the staged gate assigns when the field is absent
	d._begin_staging()
	assert_eq(d._conscripted.size(), 0,
		"no conscript_nearby field = hide-only; conscripting by default would change both shipped staged scenes without anyone asking")


func test_shipped_staged_scenes_do_not_opt_in_yet() -> void:
	# Guards the rollout: the feature ships inert. If someone later opts a
	# scene in, that's a deliberate edit, and this pin is the reminder to
	# re-check its blocking rather than a silent behavior change.
	for f in ["world1_chapter1.json", "world1_harmonia_after_cave.json"]:
		var parsed = JSON.parse_string(_read("res://data/cutscenes/%s" % f))
		assert_true(parsed is Dictionary, "%s must parse" % f)
		assert_false(parsed.has("conscript_nearby"),
			"%s opted into conscript_nearby — intentional? re-verify its blocking, then update this pin" % f)


# ── Contract 2/3: determinism, radius, cap ────────────────────────────

func test_conscripts_are_nearest_first_and_deterministic() -> void:
	var stage := _new_stage()
	# Deliberately added far-to-near so insertion order can't accidentally pass.
	_add_npc(stage, "Far", Vector2(200, 0))
	_add_npc(stage, "Near", Vector2(20, 0))
	_add_npc(stage, "Mid", Vector2(100, 0))
	var d = _new_director()
	d._conscript_spec = {"at": [0, 0], "radius": 500.0}
	d._begin_staging()
	assert_eq(d._conscripted, ["nearby_1", "nearby_2", "nearby_3"],
		"ids must be assigned nearest-first so a scene authored against nearby_1 is stable")
	var a1 = d._actors.get("nearby_1")
	assert_not_null(a1)
	assert_eq(a1.global_position, Vector2(20, 0),
		"nearby_1 must be the CLOSEST npc to the origin, not the first added")


func test_radius_excludes_distant_npcs() -> void:
	var stage := _new_stage()
	_add_npc(stage, "In", Vector2(50, 0))
	_add_npc(stage, "Out", Vector2(400, 0))
	var d = _new_director()
	d._conscript_spec = {"at": [0, 0], "radius": 100.0}
	d._begin_staging()
	assert_eq(d._conscripted.size(), 1,
		"only NPCs within `radius` become puppets — the whole point is LOCAL crowd")


func test_max_caps_conscripts() -> void:
	var stage := _new_stage()
	for i in 10:
		_add_npc(stage, "V%d" % i, Vector2(i * 5, 0))
	var d = _new_director()
	d._conscript_spec = {"at": [0, 0], "radius": 500.0, "max": 3}
	d._begin_staging()
	assert_eq(d._conscripted.size(), 3,
		"`max` must cap conscripts — a busy village would otherwise spawn a puppet per NPC")


func test_default_cap_applies_when_max_omitted() -> void:
	var stage := _new_stage()
	for i in 12:
		_add_npc(stage, "V%d" % i, Vector2(i * 5, 0))
	var d = _new_director()
	d._conscript_spec = {"at": [0, 0], "radius": 500.0}
	d._begin_staging()
	assert_eq(d._conscripted.size(), d.CONSCRIPT_MAX_DEFAULT,
		"omitting `max` must fall back to CONSCRIPT_MAX_DEFAULT, not unbounded")


# ── Contract 4: inherit the replaced NPC's look ───────────────────────

func test_conscript_inherits_npc_archetype() -> void:
	var stage := _new_stage()
	_add_npc(stage, "Smith", Vector2(10, 0), "blacksmith")
	var d = _new_director()
	d._conscript_spec = {"at": [0, 0], "radius": 100.0}
	d._begin_staging()
	# The puppet should have loaded the blacksmith sheet, not a placeholder.
	var a = d._actors.get("nearby_1")
	assert_not_null(a, "npc must be conscripted")
	assert_true(a._frames.get("0_0") is AtlasTexture,
		"conscript must load the replaced NPC's archetype sheet — a generic or placeholder would visibly change who's standing there")


func test_conscripted_npc_is_also_hidden() -> void:
	# The live NPC must still hide — otherwise the puppet renders ON TOP of it.
	var stage := _new_stage()
	var npc := _add_npc(stage, "Villager", Vector2(10, 0))
	var d = _new_director()
	d._conscript_spec = {"at": [0, 0], "radius": 100.0}
	d._begin_staging()
	assert_false(npc.visible, "the live NPC must stay hidden — its puppet stands in the same spot")
	assert_eq(d._actors["nearby_1"].global_position, npc.global_position,
		"puppet inherits the NPC's exact position so the swap is invisible")


# ── Contract 5: headless safety ───────────────────────────────────────

func test_no_stage_is_clean_noop() -> void:
	if MapSystem:
		MapSystem.current_map = null
	var d = _new_director()
	d._conscript_spec = {"at": [0, 0], "radius": 500.0}
	d._begin_staging()
	assert_eq(d._conscripted.size(), 0, "no live stage = no conscripts, no crash (story-spine walker safety)")


func test_unresolvable_origin_is_clean_noop() -> void:
	# No `at` and no live player → origin unresolvable → skip rather than
	# conscripting the whole map from (0,0).
	var stage := _new_stage()
	_add_npc(stage, "Villager", Vector2(10, 0))
	var d = _new_director()
	d._conscript_spec = {"radius": 500.0}
	d._begin_staging()
	assert_eq(d._conscripted.size(), 0,
		"unresolvable origin must skip conscription, not fall back to (0,0) and grab everyone")


func test_nearby_steps_noop_without_conscripts() -> void:
	var d = _new_director()
	d._conscripted.clear()
	d._step_nearby_face({"toward": [0, 0]})
	await d._step_nearby_scatter({"from": [0, 0]})
	assert_true(true, "nearby_* steps with nothing conscripted must resolve instantly, never await")


# ── Contract 6: teardown ──────────────────────────────────────────────

func test_end_staging_clears_conscript_state() -> void:
	var stage := _new_stage()
	var npc := _add_npc(stage, "Villager", Vector2(10, 0))
	var d = _new_director()
	d._conscript_spec = {"at": [0, 0], "radius": 100.0}
	d._begin_staging()
	assert_eq(d._conscripted.size(), 1)
	d._end_staging()
	assert_eq(d._conscripted.size(), 0, "_end_staging must clear the conscript list")
	assert_true(d._conscript_spec.is_empty(), "_end_staging must clear the spec so the next scene starts opted-out")
	assert_true(npc.visible, "teardown restores the conscripted NPC")
	assert_true(d._actors.is_empty(), "conscript puppets are freed with the rest")


# ── Dispatch wiring ───────────────────────────────────────────────────

func test_nearby_steps_are_dispatched() -> void:
	# Same pin as every other step type: a handler nobody routes to is dead code.
	var src := _read(DIRECTOR)
	assert_gt(src.find('"nearby_face":'), -1, "nearby_face must have a quoted dispatch arm in _execute_step")
	assert_gt(src.find('"nearby_scatter":'), -1, "nearby_scatter must have a quoted dispatch arm in _execute_step")
	assert_gt(src.find("func _step_nearby_face("), -1, "nearby_face handler must exist")
	assert_gt(src.find("func _step_nearby_scatter("), -1, "nearby_scatter handler must exist")


func test_scatter_starts_walks_in_parallel_not_serially() -> void:
	# A serial `for a in conscripts: await a.walk_to(...)` makes the crowd
	# shuffle aside single-file over N × duration. Pin the parallel shape:
	# start every walk unawaited, then wait out the longest.
	var src := _read(DIRECTOR)
	var fn := src.find("func _step_nearby_scatter(")
	assert_gt(fn, -1)
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_eq(body.find("await a.walk_to"), -1,
		"scatter must NOT await each walk in turn — that serializes the crowd into a queue")
	assert_gt(body.find("longest"), -1,
		"scatter must track the longest walk and await that once")
