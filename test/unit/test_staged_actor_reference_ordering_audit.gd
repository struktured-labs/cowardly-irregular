extends GutTest

## A staged step that names an actor which isn't on stage FAILS SILENTLY.
##
## _get_actor returns null on a miss with no warning, and the callers treat that
## as "nothing to do":
##   camera_focus  target resolves to Vector2.INF -> bare `return`, the camera
##                 never moves and the scene's intended framing simply doesn't
##                 happen. Nothing is logged.
##   emote/hop/face_actor/move_actor/despawn_actor  no-op on a null actor.
##
## Two ways to author it, and the second is the one that bites:
##   1. a typo'd or never-spawned id
##   2. ORDERING — the id is real, the actor was spawned, and the step sits
##      AFTER its despawn_actor (or before its spawn)
##
## Ordering is live in this lane: world1_mordaine_watch_road grew a
## despawn_actor mid-scene (2026-07-26) so the narration would stop describing
## someone still standing there. Its camera_focus targets the actor BY ID. Move
## either step past the other and the camera silently stops working, the suite
## stays green, and the only symptom is a scene that doesn't frame anything.
##
## Corpus at the time of writing: 193 scenes, 47 actor references, 0 violations.
## This is a ratchet against the class entering, not a fix for a live defect.

const CUTSCENE_DIR := "res://data/cutscenes"

## Steps whose `id` must name an actor currently on stage.
const ACTOR_ID_STEPS := ["move_actor", "face_actor", "emote", "hop", "despawn_actor"]

## conscript_nearby materialises `nearby_1..N` at runtime from whoever is in
## radius, so their ids are legitimate without a spawn_actor step. Bounded well
## above CONSCRIPT_MAX_DEFAULT — this must not become a way to launder a typo.
const CONSCRIPT_ID_LIMIT := 12


## Returns violations as readable strings. `live` is threaded so a spawn inside
## a branch case counts for later steps, matching the director's flat _actors dict.
func _violations(data: Dictionary, label: String) -> Array:
	var out: Array = []
	var live: Dictionary = {}
	if data.get("conscript_nearby") != null:
		for i in range(1, CONSCRIPT_ID_LIMIT + 1):
			live["nearby_%d" % i] = true
	_walk(data.get("steps", []), "steps", live, out, label)
	return out


func _walk(steps, path: String, live: Dictionary, out: Array, label: String) -> void:
	if not (steps is Array):
		return
	var idx := 0
	for step in steps:
		if not (step is Dictionary):
			idx += 1
			continue
		var t := str(step.get("type", ""))
		if t == "spawn_actor":
			live[str(step.get("id", ""))] = true
		elif t in ACTOR_ID_STEPS:
			var aid := str(step.get("id", ""))
			if not live.has(aid):
				out.append("%s %s[%d] %s id '%s' is not on stage — the step no-ops silently" % [
					label, path, idx, t, aid])
			if t == "despawn_actor":
				live.erase(aid)
		elif t == "camera_focus" and step.get("target") is String:
			var tid := str(step["target"])
			if not live.has(tid):
				out.append("%s %s[%d] camera_focus target '%s' is not on stage — the camera never moves and nothing is logged" % [
					label, path, idx, tid])
		for key in (step.get("cases", {}) as Dictionary):
			_walk(step["cases"][key], "%s[%d].cases.%s" % [path, idx, key], live, out, label)
		for key in ["if_true", "if_false"]:
			if step.get(key) != null:
				_walk(step[key], "%s[%d].%s" % [path, idx, key], live, out, label)
		idx += 1


func _all_scenes() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(CUTSCENE_DIR)
	assert_not_null(dir, "cutscenes dir must open")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENE_DIR, f]))
		if parsed is Dictionary:
			out[f] = parsed
	return out


func _reference_count(data: Dictionary) -> int:
	return _count_refs(data.get("steps", []))


func _count_refs(steps) -> int:
	if not (steps is Array):
		return 0
	var n := 0
	for step in steps:
		if not (step is Dictionary):
			continue
		var t := str(step.get("type", ""))
		if t in ACTOR_ID_STEPS or (t == "camera_focus" and step.get("target") is String):
			n += 1
		for key in (step.get("cases", {}) as Dictionary):
			n += _count_refs(step["cases"][key])
		for key in ["if_true", "if_false"]:
			n += _count_refs(step.get(key))
	return n


func test_no_step_references_an_actor_that_is_not_on_stage() -> void:
	var scenes := _all_scenes()
	assert_gt(scenes.size(), 100,
		"POSITIVE CONTROL: the corpus must parse — a small number here makes the result below vacuous")
	var refs := 0
	var offenders: Array = []
	for f in scenes:
		refs += _reference_count(scenes[f])
		offenders.append_array(_violations(scenes[f], f))
	# Without this, an empty offender list could mean "no references exist".
	assert_gt(refs, 20,
		"POSITIVE CONTROL: the corpus must contain actor references to check — got %d" % refs)
	assert_eq(offenders.size(), 0,
		"staged steps must reference actors that are on stage:\n  %s" % "\n  ".join(offenders))


## ── Controls, synthetic on purpose ────────────────────────────────────
## The corpus is clean, so it cannot demonstrate that this audit can FAIL.
## These are hand-built so they keep proving it after the corpus changes.

func test_control_flags_a_camera_target_that_was_never_spawned() -> void:
	var v := _violations({"steps": [{"type": "camera_focus", "target": "ghost"}]}, "synthetic")
	assert_eq(v.size(), 1, "a camera_focus naming an unspawned actor must be flagged")
	assert_true(str(v[0]).contains("never moves"), "the message must name the consequence, got: %s" % v[0])


func test_control_flags_a_step_after_the_actor_is_despawned() -> void:
	# THE ordering case. The id is real and the actor WAS on stage — the defect
	# is purely where the step sits relative to despawn_actor.
	var v := _violations({"steps": [
		{"type": "spawn_actor", "id": "m", "kind": "npc", "archetype": "x"},
		{"type": "despawn_actor", "id": "m"},
		{"type": "emote", "id": "m", "emote": "exclaim"},
	]}, "synthetic")
	assert_eq(v.size(), 1, "referencing an actor after its despawn must be flagged — this is the authoring mistake the audit exists for")


func test_control_correct_ordering_is_not_flagged() -> void:
	# NEGATIVE CONTROL: an audit that flags correct scenes gets weakened by
	# whoever hits it next, which is how exemption lists start.
	var v := _violations({"steps": [
		{"type": "spawn_actor", "id": "m", "kind": "npc", "archetype": "x"},
		{"type": "camera_focus", "target": "m"},
		{"type": "emote", "id": "m", "emote": "exclaim"},
		{"type": "despawn_actor", "id": "m"},
	]}, "synthetic")
	assert_eq(v.size(), 0, "a correctly ordered scene must pass, got: %s" % str(v))


func test_control_a_branch_nested_spawn_counts_as_on_stage() -> void:
	# The director keeps one flat _actors dict, so an actor spawned inside a
	# branch case is genuinely available afterwards. Modelling branches as
	# separate scopes would flag correct scenes.
	var v := _violations({"steps": [
		{"type": "branch", "condition": "x", "cases": {
			"a": [{"type": "spawn_actor", "id": "m", "kind": "npc", "archetype": "x"}]}},
		{"type": "emote", "id": "m", "emote": "exclaim"},
	]}, "synthetic")
	assert_eq(v.size(), 0, "a spawn inside a branch case must count as on stage, got: %s" % str(v))


func test_control_an_array_camera_target_is_never_an_actor_reference() -> void:
	# camera_focus takes EITHER an actor id or a literal [x,y]. Treating the
	# array form as an id would flag every coordinate pan in the corpus.
	var v := _violations({"steps": [{"type": "camera_focus", "target": [100, 200]}]}, "synthetic")
	assert_eq(v.size(), 0, "an [x,y] camera target is a coordinate, not an actor id, got: %s" % str(v))
